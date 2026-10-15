import { createBrowserClient } from "@supabase/ssr"

import { requireSupabaseConfig } from "./config"

/**
 * Creates a Supabase client for use in Client Components (browser).
 *
 * `createBrowserClient` reuses a single instance internally, so calling this
 * from multiple components is safe and does not create duplicate clients.
 * Throws a descriptive error when Supabase is not configured.
 */
export function createClient() {
  const { url, publishableKey } = requireSupabaseConfig()

  return createBrowserClient(url, publishableKey)
}
