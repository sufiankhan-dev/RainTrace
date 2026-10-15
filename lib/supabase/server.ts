import "server-only"

import { createServerClient } from "@supabase/ssr"
import { cookies } from "next/headers"

import { requireSupabaseConfig } from "./config"

/**
 * Creates a Supabase client for use on the server: Server Components, Server
 * Actions, and Route Handlers. Must be called per request so it reads the
 * request's cookies. Throws a descriptive error when Supabase is unconfigured.
 */
export async function createClient() {
  const { url, publishableKey } = requireSupabaseConfig()
  const cookieStore = await cookies()

  return createServerClient(url, publishableKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll()
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) => {
            cookieStore.set(name, value, options)
          })
        } catch {
          // `setAll` was called from a Server Component, where cookies cannot
          // be written. Safe to ignore while `proxy.ts` refreshes sessions.
        }
      },
    },
  })
}
