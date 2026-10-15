import { NextResponse } from "next/server"

import { createAdminClient } from "@/lib/supabase/admin"
import { getSupabaseConfig } from "@/lib/supabase/config"

/**
 * Read-only health check for the Supabase connection.
 *
 * Proves, without writing anything:
 *   1. config   — the public Supabase env vars are present.
 *   2. restApi  — the project is reachable and the publishable key is accepted.
 *   3. schema   — the three migrated tables exist in `public` and are correctly
 *                 denied to the publishable key (42501). PGRST205 means the
 *                 migrations have not been applied to this project yet.
 *   4. databaseQueries — real `select(id).limit(1)` queries on all three tables
 *                 through the server-only service-role client. Skipped when
 *                 SUPABASE_SERVICE_ROLE_KEY is unset, because `anon` has no
 *                 grants by design and cannot prove the query path.
 *   5. storage   — the private `findings` bucket exists and is not public.
 *
 * Statuses: ok | degraded | error | skipped. Overall status is
 * error > degraded > ok (skipped never affects it). HTTP 200 only when the
 * overall status is `ok`; otherwise 503. No keys or row data are ever returned.
 *
 * The project enables `cacheComponents`, so a route-handler segment config like
 * `export const dynamic` is not allowed here. GET handlers are uncached by
 * default under `cacheComponents`; the response also sends `Cache-Control:
 * no-store` so proxies do not cache a health result.
 */

const TABLES = ["properties", "inspections", "findings"] as const
const PHOTO_BUCKET = "findings"
const REQUEST_TIMEOUT_MS = 5000

type CheckStatus = "ok" | "degraded" | "error" | "skipped"

type Check = {
  status: CheckStatus
  message: string
}

type HealthReport = {
  status: "ok" | "degraded" | "error"
  timestamp: string
  checks: {
    config: Check
    restApi: Check
    schema: Check
    databaseQueries: Check
    storage: Check
  }
}

type PostgrestProbe =
  | { kind: "readable" }
  | { kind: "present" }
  | { kind: "missing" }
  | { kind: "invalid_key" }
  | { kind: "unreachable" }
  | { kind: "unexpected"; message: string }

function describeError(error: unknown): string {
  if (error instanceof Error) {
    if (error.name === "TimeoutError") {
      return `timed out after ${REQUEST_TIMEOUT_MS}ms`
    }
    return error.message
  }
  return String(error)
}

function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`timed out after ${timeoutMs}ms`))
    }, timeoutMs)

    promise.then(
      (value) => {
        clearTimeout(timer)
        resolve(value)
      },
      (error) => {
        clearTimeout(timer)
        reject(error)
      },
    )
  })
}

/**
 * Queries one table with the publishable key and classifies the response.
 * Read-only: `select=id&limit=1` never returns more than one id and is only
 * inspected for its status/shape, never for row content.
 */
async function probeTable(
  url: string,
  publishableKey: string,
  table: string,
): Promise<PostgrestProbe> {
  try {
    const response = await fetch(
      `${url}/rest/v1/${table}?select=id&limit=1`,
      {
        method: "GET",
        headers: {
          apikey: publishableKey,
          Authorization: `Bearer ${publishableKey}`,
          Accept: "application/json",
        },
        cache: "no-store",
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      },
    )

    if (response.ok) {
      return { kind: "readable" }
    }

    const body = (await response.json().catch(() => null)) as {
      code?: string
      message?: string
    } | null
    const code = body?.code
    const message = body?.message ?? ""

    if (code === "42501" || message.includes("permission denied")) {
      return { kind: "present" }
    }
    if (code === "PGRST205") {
      return { kind: "missing" }
    }
    if (message.includes("Invalid API key")) {
      return { kind: "invalid_key" }
    }
    return {
      kind: "unexpected",
      message: `HTTP ${response.status}${message ? `: ${message}` : ""}`,
    }
  } catch {
    // Network failure or timeout — either way the project is unreachable.
    return { kind: "unreachable" }
  }
}

function classifyRestApi(probes: PostgrestProbe[]): Check {
  const unexpected = probes.find(
    (probe): probe is { kind: "unexpected"; message: string } =>
      probe.kind === "unexpected",
  )

  if (probes.every((probe) => probe.kind === "unreachable")) {
    return {
      status: "error",
      message: `Supabase project unreachable (each request failed or timed out after ${REQUEST_TIMEOUT_MS}ms). Check NEXT_PUBLIC_SUPABASE_URL and network access.`,
    }
  }

  if (probes.some((probe) => probe.kind === "invalid_key")) {
    return {
      status: "error",
      message:
        "Supabase rejected the publishable key (Invalid API key). Check NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY.",
    }
  }

  if (probes.every((probe) => probe.kind === "unexpected")) {
    return {
      status: "error",
      message: `Unexpected response from the Supabase REST API: ${unexpected?.message ?? "unknown"}`,
    }
  }

  return {
    status: "ok",
    message: "Project reachable and publishable key accepted.",
  }
}

function classifySchema(probes: PostgrestProbe[]): Check {
  const missing = TABLES.filter((_, index) => probes[index].kind === "missing")
  const readable = TABLES.filter(
    (_, index) => probes[index].kind === "readable",
  )
  const unexpected = TABLES.filter(
    (_, index) => probes[index].kind === "unexpected",
  )

  if (missing.length > 0) {
    return {
      status: "degraded",
      message: `Tables missing from the public schema: ${missing.join(", ")}. Apply the migrations: supabase link --project-ref <ref> && supabase db push.`,
    }
  }

  if (readable.length > 0) {
    return {
      status: "error",
      message: `Tables readable by the publishable key: ${readable.join(", ")}. Expected denial — grants are revoked and RLS enabled by the migrations.`,
    }
  }

  if (unexpected.length > 0) {
    return {
      status: "degraded",
      message: `Unexpected response for: ${unexpected.join(", ")}. See the restApi check for details.`,
    }
  }

  return {
    status: "ok",
    message: "properties, inspections, findings exist in the public schema and are correctly denied to the publishable key.",
  }
}

async function checkDatabaseQueries(): Promise<Check> {
  const admin = createAdminClient()

  if (!admin) {
    return {
      status: "skipped",
      message:
        "SUPABASE_SERVICE_ROLE_KEY is not set. Only the service-role client can prove the query path until authentication ships (anon has no grants by design).",
    }
  }

  const failures: string[] = []

  for (const table of TABLES) {
    try {
      const { error } = await admin
        .from(table)
        .select("id")
        .limit(1)
        .abortSignal(AbortSignal.timeout(REQUEST_TIMEOUT_MS))

      if (error) {
        failures.push(`${table}: ${error.message}`)
      }
    } catch (error) {
      failures.push(`${table}: ${describeError(error)}`)
    }
  }

  if (failures.length > 0) {
    return {
      status: "error",
      message: `SELECT failed (${failures.join("; ")}). Missing tables mean the migrations were not applied to this project.`,
    }
  }

  return {
    status: "ok",
    message: `SELECT ... LIMIT 1 succeeded on ${TABLES.join(", ")}.`,
  }
}

async function checkStorage(): Promise<Check> {
  const admin = createAdminClient()

  if (!admin) {
    return {
      status: "skipped",
      message:
        "SUPABASE_SERVICE_ROLE_KEY is not set, so the private photo bucket was not checked.",
    }
  }

  try {
    const { data, error } = await withTimeout(
      admin.storage.getBucket(PHOTO_BUCKET),
      REQUEST_TIMEOUT_MS,
    )

    if (error) {
      const missing =
        error.message.toLowerCase().includes("not found") ||
        (error as { status?: number }).status === 404

      return missing
        ? {
            status: "error",
            message: `Private bucket "${PHOTO_BUCKET}" not found. Apply the storage migration: supabase db push.`,
          }
        : {
            status: "error",
            message: `Bucket lookup failed: ${error.message}`,
          }
    }

    if (data?.public === true) {
      return {
        status: "error",
        message: `Bucket "${PHOTO_BUCKET}" is public; the migration creates it as private.`,
      }
    }

    return {
      status: "ok",
      message: `Private bucket "${PHOTO_BUCKET}" exists.`,
    }
  } catch (error) {
    return {
      status: "error",
      message: `Storage API unreachable: ${describeError(error)}`,
    }
  }
}

function rollUp(checks: HealthReport["checks"]): HealthReport["status"] {
  const statuses = Object.values(checks).map((check) => check.status)

  if (statuses.includes("error")) {
    return "error"
  }
  if (statuses.includes("degraded")) {
    return "degraded"
  }
  return "ok"
}

export async function GET(): Promise<NextResponse<HealthReport>> {
  const config = getSupabaseConfig()

  const checks: HealthReport["checks"] = {
    config: config
      ? {
          status: "ok",
          message:
            "NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY are set.",
        }
      : {
          status: "error",
          message:
            "Supabase is not configured. Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY (see .env.example).",
        },
    restApi: { status: "skipped", message: "Not evaluated: Supabase is not configured." },
    schema: { status: "skipped", message: "Not evaluated: Supabase is not configured." },
    databaseQueries: { status: "skipped", message: "Not evaluated: Supabase is not configured." },
    storage: { status: "skipped", message: "Not evaluated: Supabase is not configured." },
  }

  if (config) {
    const probes = await Promise.all(
      TABLES.map((table) => probeTable(config.url, config.publishableKey, table)),
    )

    checks.restApi = classifyRestApi(probes)

    if (checks.restApi.status === "ok") {
      checks.schema = classifySchema(probes)

      // Only spend service-role queries when the project actually answered;
      // an unreachable project would just burn the timeouts again.
      const reachable = probes.some(
        (probe) => probe.kind !== "unreachable" && probe.kind !== "invalid_key",
      )
      if (reachable) {
        checks.databaseQueries = await checkDatabaseQueries()
        checks.storage = await checkStorage()
      }
    }
  }

  const status = rollUp(checks)

  return NextResponse.json(
    { status, timestamp: new Date().toISOString(), checks },
    {
      status: status === "ok" ? 200 : 503,
      headers: { "Cache-Control": "no-store" },
    },
  )
}
