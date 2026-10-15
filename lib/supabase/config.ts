const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
const supabasePublishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY

const MISSING_CONFIG_MESSAGE =
  "Supabase is not configured. Set NEXT_PUBLIC_SUPABASE_URL and " +
  "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY in your environment (see .env.example)."

export type SupabaseConfig = {
  url: string
  publishableKey: string
}

/**
 * True when the public Supabase URL and publishable key are both present.
 * Use this to render setup or "not configured" states instead of crashing.
 */
export const isSupabaseConfigured = Boolean(
  supabaseUrl && supabasePublishableKey,
)

/**
 * Returns the public Supabase configuration, or `null` when the environment
 * variables are missing. Never throws, so it is safe to call while rendering.
 */
export function getSupabaseConfig(): SupabaseConfig | null {
  if (!supabaseUrl || !supabasePublishableKey) {
    return null
  }

  return { url: supabaseUrl, publishableKey: supabasePublishableKey }
}

/**
 * Returns the public Supabase configuration or throws a descriptive error.
 * Call this only at the point a client is actually being created so a missing
 * configuration never breaks module import or an otherwise static render.
 */
export function requireSupabaseConfig(): SupabaseConfig {
  const config = getSupabaseConfig()

  if (!config) {
    throw new Error(MISSING_CONFIG_MESSAGE)
  }

  return config
}
