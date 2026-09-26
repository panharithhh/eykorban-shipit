import { Database, ExternalLink, FileCode2, KeyRound } from "lucide-react"

import { Logo } from "@/components/logo"

/**
 * Shown instead of the app when .env.local has no Supabase credentials. The
 * alternative is a blank page and a console error, which tells a new teammate
 * cloning this repo nothing at all.
 */
const STEPS = [
  {
    icon: Database,
    title: "Create a Supabase project",
    body: (
      <>
        Sign in at{" "}
        <a
          href="https://supabase.com/dashboard"
          target="_blank"
          rel="noreferrer"
          className="font-medium text-primary hover:underline dark:text-rose-400"
        >
          supabase.com/dashboard
          <ExternalLink className="ml-0.5 inline size-3" />
        </a>{" "}
        and create one. Provisioning takes about two minutes.
      </>
    ),
  },
  {
    icon: FileCode2,
    title: "Run the database script",
    body: (
      <>
        In the SQL Editor, paste and run{" "}
        <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
          supabase/setup-new-project.sql
        </code>
        . It creates every table and security rule, then loads the demo data.
      </>
    ),
  },
  {
    icon: KeyRound,
    title: "Add your keys",
    body: (
      <>
        Run{" "}
        <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
          cp .env.example .env.local
        </code>
        , then paste the Project URL and the{" "}
        <strong className="font-medium text-foreground">publishable</strong> key
        (
        <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
          sb_publishable_…
        </code>
        ) from Settings → API Keys. Restart the dev server afterwards — Vite
        only reads env files at startup. On Vercel, add the same two under
        Settings → Environment Variables instead, then redeploy.
      </>
    ),
  },
]

export function SupabaseSetupNotice() {
  return (
    <main className="flex min-h-svh items-center justify-center bg-muted/40 px-4 py-12">
      <div className="w-full max-w-xl rounded-3xl border border-border bg-card p-8 shadow-xs sm:p-10">
        <Logo className="h-8" />

        <h1 className="mt-6 text-2xl font-semibold tracking-tight">
          Connect a Supabase project
        </h1>
        <p className="mt-2 text-sm text-muted-foreground">
          The app reads its data from Supabase and cannot start without
          credentials. Three steps, about ten minutes — more detail is in{" "}
          <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
            README.md
          </code>
          .
        </p>

        <ol className="mt-8 flex flex-col gap-6">
          {STEPS.map(({ icon: Icon, title, body }, index) => (
            <li key={title} className="flex gap-4">
              <div className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary dark:text-rose-400">
                <Icon className="size-4.5" />
              </div>
              <div className="min-w-0">
                <p className="text-sm font-semibold">
                  {index + 1}. {title}
                </p>
                <p className="mt-1 text-sm leading-relaxed text-muted-foreground">
                  {body}
                </p>
              </div>
            </li>
          ))}
        </ol>

        <p className="mt-8 rounded-xl bg-muted/70 px-4 py-3 text-xs leading-relaxed text-muted-foreground">
          <strong className="font-medium text-foreground">
            Never add the secret key
          </strong>{" "}
          (<code className="text-xs">sb_secret_…</code> or the legacy{" "}
          <code className="text-xs">service_role</code>) to this file. Vite
          inlines every <code className="text-xs">VITE_</code> variable into the
          bundle it serves to users, and those keys bypass every Row Level
          Security policy.
        </p>
      </div>
    </main>
  )
}
