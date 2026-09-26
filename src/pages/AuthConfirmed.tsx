import { Link, Navigate } from "react-router"
import { MailCheck, MailWarning } from "lucide-react"

import { useAuth } from "@/components/auth-provider"
import { EmptyState } from "@/components/empty-state"
import { buttonVariants } from "@/components/ui/button"
import { cn } from "@/lib/utils"

/**
 * Where the sign-up confirmation email sends people (emailRedirectTo in
 * auth-provider.tsx).
 *
 * Supabase appends the new session to the URL fragment, and supabase-js
 * (detectSessionInUrl) signs the browser in before the app renders, so by the
 * time this page runs there is either a session or a reason there is not.
 * A failed link (expired, already used) arrives as `#error_description=…`,
 * which supabase-js leaves in place.
 */
function linkError(): string | null {
  const params = new URLSearchParams(window.location.hash.slice(1))
  return params.get("error_description") ?? params.get("error")
}

const AuthConfirmed = () => {
  const { session } = useAuth()
  const error = linkError()

  if (session) return <Navigate to="/" replace />

  return (
    <main className="flex min-h-svh items-center justify-center bg-muted/50 px-4 py-12">
      <div className="w-full max-w-md">
        {error ? (
          <EmptyState
            icon={MailWarning}
            title="That link didn't work"
            description={`${error}. Links expire after a while and work once. Try signing in; if your email isn't confirmed yet, sign up again for a fresh link.`}
            action={
              <Link to="/login" className={cn(buttonVariants())}>
                Go to sign in
              </Link>
            }
          />
        ) : (
          <EmptyState
            icon={MailCheck}
            title="Your email is confirmed"
            description="Sign in to continue."
            action={
              <Link to="/login" className={cn(buttonVariants())}>
                Sign in
              </Link>
            }
          />
        )}
      </div>
    </main>
  )
}

export default AuthConfirmed
