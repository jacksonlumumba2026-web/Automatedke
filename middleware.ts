import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Runs on every matched request. Two jobs, per Authentication_Specification.md
 * Section 6.6:
 *   1. Refresh the Supabase session (required for SSR auth to keep
 *      working — without this, access tokens silently expire mid-session).
 *   2. Block unauthenticated access to protected route groups before any
 *      Server Component even starts rendering.
 *
 * This is NOT where organization-membership/role checks happen — those
 * are enforced in the [orgSlug] layout (Section 7, Multi-Tenant
 * Architecture) since they need the URL's org slug, which isn't reliably
 * available at this layer for every route shape. Middleware only answers
 * "is there a valid session at all."
 */
export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request: { headers: request.headers } });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          request.cookies.set({ name, value, ...options });
          response = NextResponse.next({ request: { headers: request.headers } });
          response.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
          request.cookies.set({ name, value: "", ...options });
          response = NextResponse.next({ request: { headers: request.headers } });
          response.cookies.set({ name, value: "", ...options });
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname } = request.nextUrl;
  const isAuthRoute = pathname.startsWith("/login") || pathname.startsWith("/signup");
  const isPublicRoute =
    pathname === "/" ||
    isAuthRoute ||
    pathname.startsWith("/forgot-password") ||
    pathname.startsWith("/reset-password") ||
    pathname.startsWith("/verify-email") ||
    pathname.startsWith("/accept-invite") ||
    pathname.startsWith("/auth/callback") ||
    pathname.startsWith("/api/health");

  if (!user && !isPublicRoute) {
    const redirectUrl = new URL("/login", request.url);
    redirectUrl.searchParams.set("redirectTo", pathname);
    return NextResponse.redirect(redirectUrl);
  }

  if (user && isAuthRoute) {
    // Already signed in — don't show login/signup again.
    return NextResponse.redirect(new URL("/", request.url));
  }

  return response;
}

export const config = {
  matcher: [
    /*
     * Match everything except static assets and Next.js internals —
     * running middleware on every real navigation/data request is what
     * keeps the session cookie fresh; excluding these paths is a
     * performance optimization, not a security boundary (see the
     * [orgSlug] layout for the actual authorization checks).
     */
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
