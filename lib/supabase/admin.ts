import "server-only"

import { createClient, type SupabaseClient } from "@supabase/supabase-js"

import { getSupabaseConfig } from "./config"

/**
 * Creates a Supabase client using the service-role key for privileged,
 * server-only tasks (for example trusted background jobs or admin operations).
 *
 * The service-role key bypasses Row Level Security, so this client must never
 * be imported into Client Components or exposed to the browser. `server-only`
 * enforces that at build time.
 *
 * Returns `null` when the service-role key is not configured, so callers can
 * handle the missing-configuration case without crashing.
 */
export function createAdminClient(): SupabaseClient | null {
  const config = getSupabaseConfig()
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY

  if (!config || !serviceRoleKey) {
    return null
  }

  return createClient(config.url, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  })
}
