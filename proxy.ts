import { createServerClient } from "@supabase/ssr"
import { NextResponse, type NextRequest } from "next/server"

import { getSupabaseConfig } from "@/lib/supabase/config"

/**
 * Refreshes the Supabase Auth session on every request so Server Components
 * always see a valid session. This is the official Supabase approach for
 * Next.js (Next.js 16 renamed `middleware` to `proxy`).
 *
 * When Supabase is not configured the proxy is a no-op, so the app still
 * serves normally without environment variables set.
 */
export async function proxy(request: NextRequest) {
  const config = getSupabaseConfig()

  if (!config) {
    return NextResponse.next({ request })
  }

  let supabaseResponse = NextResponse.next({ request })

  const supabase = createServerClient(config.url, config.publishableKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll()
      },
      setAll(cookiesToSet, headers) {
        cookiesToSet.forEach(({ name, value }) => {
          request.cookies.set(name, value)
        })

        supabaseResponse = NextResponse.next({ request })

        cookiesToSet.forEach(({ name, value, options }) => {
          supabaseResponse.cookies.set(name, value, options)
        })

        Object.entries(headers).forEach(([key, value]) => {
          supabaseResponse.headers.set(key, value)
        })
      },
    },
  })

  // IMPORTANT: keep this immediately after creating the client and do not run
  // any logic between the two calls, or the refreshed session may be lost.
  await supabase.auth.getClaims()

  return supabaseResponse
}

export const config = {
  matcher: [
    /*
     * Match all request paths except static assets and image files so the
     * proxy does not run on resources that never use Supabase.
     */
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
}
