import * as React from "react"
import { Link, useLocation, useNavigate } from "react-router"
import { Search, LogOut, Menu, X, Sun, Moon, Languages } from "lucide-react"

import { useAuth } from "@/components/auth-provider"
import { useLanguage } from "@/components/language-provider"
import { useTheme } from "@/components/theme-provider"
import { Logo } from "@/components/logo"
import { buttonVariants } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { RoleName } from "@/interface/user"
import { getInitials } from "@/lib/format"
import type { MessageKey } from "@/lib/i18n"
import { cn } from "@/lib/utils"

type NavLink = { label: MessageKey; href: string }

const publicLinks: NavLink[] = [
  { label: "nav.explore", href: "/" },
  { label: "nav.hireCreatives", href: "/hire-creatives" },
  { label: "nav.findWork", href: "/find-work" },
]

// Clients have no sidebar, so their own pages live here instead. Find Work
// lists jobs for freelancers to answer, which a client has no use for.
const clientLinks: NavLink[] = [
  { label: "nav.explore", href: "/" },
  { label: "nav.hireCreatives", href: "/hire-creatives" },
  { label: "nav.projects", href: "/projects" },
  { label: "nav.myJobs", href: "/my-jobs" },
]

function isActiveLink(href: string, path: string) {
  return href === "/" ? path === "/" : path.startsWith(href)
}

// WebKit draws its own clear button in search inputs, on top of the ⌘K hint.
const SEARCH_INPUT =
  "[&::-webkit-search-cancel-button]:appearance-none [&::-webkit-search-decoration]:appearance-none"

export function Header() {
  const { theme, setTheme } = useTheme()
  const { language, setLanguage, t } = useLanguage()
  const { user, signOut } = useAuth()
  const navigate = useNavigate()
  // Reading the router's location keeps the active-link underline correct after
  // a client-side navigation; window.location.pathname never re-rendered.
  const location = useLocation()
  const currentPath = location.pathname
  const [isMobileMenuOpen, setIsMobileMenuOpen] = React.useState(false)
  const searchInputRef = React.useRef<HTMLInputElement>(null)

  const navLinks = user?.role === RoleName.CLIENT ? clientLinks : publicLinks

  // On the results page the box shows what was searched; elsewhere it starts
  // empty. Keying the inputs by it resets them without syncing state by hand.
  const searchedFor =
    currentPath === "/search"
      ? (new URLSearchParams(location.search).get("q") ?? "")
      : ""

  function handleSearch(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const query = String(new FormData(event.currentTarget).get("q") ?? "")
    if (!query.trim()) return

    setIsMobileMenuOpen(false)
    navigate(`/search?q=${encodeURIComponent(query.trim())}`)
  }

  // The ⌘K hint was decoration; now ⌘K (Ctrl+K elsewhere) focuses the box.
  React.useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault()
        searchInputRef.current?.focus()
        searchInputRef.current?.select()
      }
    }

    window.addEventListener("keydown", onKeyDown)
    return () => window.removeEventListener("keydown", onKeyDown)
  }, [])

  const isDark =
    theme === "dark" ||
    (theme === "system" &&
      typeof window !== "undefined" &&
      window.matchMedia("(prefers-color-scheme: dark)").matches)

  const toggleTheme = () => {
    setTheme(isDark ? "light" : "dark")
  }

  return (
    <header className="sticky top-0 z-50 w-full border-b border-border/80 bg-background/80 shadow-xs backdrop-blur-md transition-colors">
      <div className="mx-auto flex w-full max-w-[1440px] items-center justify-between gap-4 px-4 py-3 sm:px-6">
        <div className="flex max-w-xl flex-1 items-center gap-6 md:gap-8">
          <Link
            to="/"
            className="group flex shrink-0 items-center no-underline outline-none"
          >
            <Logo className="h-7 transition-transform group-hover:scale-105" />
          </Link>

          <form
            role="search"
            onSubmit={handleSearch}
            className="relative hidden w-full max-w-md sm:block"
          >
            <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3.5 text-muted-foreground">
              <Search className="size-4" />
            </div>
            <Input
              key={searchedFor}
              ref={searchInputRef}
              type="search"
              name="q"
              enterKeyHint="search"
              defaultValue={searchedFor}
              aria-label={t("header.searchLabel")}
              placeholder={t("header.search")}
              className={cn(
                "h-9 w-full rounded-lg border-border/70 bg-muted/40 pr-12 pl-9 text-sm transition-all placeholder:text-muted-foreground/70 focus-visible:bg-background focus-visible:ring-1 focus-visible:ring-primary",
                SEARCH_INPUT
              )}
            />
            <div className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-2.5">
              <kbd className="rounded border border-border/60 bg-muted px-1.5 py-0.5 text-[10px] font-semibold text-muted-foreground shadow-2xs">
                ⌘K
              </kbd>
            </div>
          </form>
        </div>

        <nav className="hidden items-center gap-6 md:flex lg:gap-7">
          {navLinks.map((link) => {
            const isActive = isActiveLink(link.href, currentPath)
            return (
              <Link
                key={link.href}
                to={link.href}
                aria-current={isActive ? "page" : undefined}
                className={`pb-1 text-sm transition-colors ${
                  isActive
                    ? "border-b-2 border-primary font-medium text-foreground"
                    : "font-normal text-muted-foreground hover:text-foreground"
                }`}
              >
                {t(link.label)}
              </Link>
            )
          })}
        </nav>

        <div className="flex items-center gap-2 sm:gap-3">
          {/* Labelled with the language it switches TO, written in that
              language, so a reader of either one can find it — the same way
              the theme button shows the mode it switches to. */}
          <button
            type="button"
            onClick={() => setLanguage(language === "en" ? "km" : "en")}
            aria-label={t("header.toOtherLanguage")}
            title={t("header.toOtherLanguage")}
            className="flex h-9 cursor-pointer items-center gap-1.5 rounded-lg px-2 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          >
            <Languages className="hidden size-4 sm:block" />
            {language === "en" ? <span lang="km">ខ្មែរ</span> : <span lang="en">EN</span>}
          </button>
          <button
            type="button"
            onClick={toggleTheme}
            aria-label={isDark ? t("header.toLight") : t("header.toDark")}
            className="flex size-9 cursor-pointer items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          >
            {isDark ? (
              <Sun className="size-4 text-amber-500 transition-transform" />
            ) : (
              <Moon className="size-4 transition-transform" />
            )}
          </button>
          {/* The notifications bell was removed: it showed a permanent unread
              dot and was wired to nothing. */}

          {user ? (
            <>
              <Link
                to="/profile"
                aria-label={t("header.profile")}
                aria-current={currentPath === "/profile" ? "page" : undefined}
                className={`ml-0.5 cursor-pointer rounded-full p-0.5 ring-1 transition-all hover:ring-primary ${
                  currentPath === "/profile" ? "ring-primary" : "ring-border"
                }`}
              >
                <Avatar className="size-8">
                  {user.avatarUrl && (
                    <AvatarImage src={user.avatarUrl} alt={user.name} />
                  )}
                  <AvatarFallback className="text-xs font-medium">
                    {getInitials(user.name)}
                  </AvatarFallback>
                </Avatar>
              </Link>

              <button
                type="button"
                aria-label={t("header.signOut")}
                title={t("header.signOut")}
                onClick={async () => {
                  await signOut()
                  navigate("/")
                }}
                className="flex size-9 cursor-pointer items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
              >
                <LogOut className="size-4" />
              </button>
            </>
          ) : (
            <div className="hidden items-center gap-2 sm:flex">
              <Link
                to="/login"
                className={cn(buttonVariants({ variant: "ghost", size: "sm" }))}
              >
                {t("header.signIn")}
              </Link>
              <Link to="/signup" className={cn(buttonVariants({ size: "sm" }))}>
                {t("header.signUp")}
              </Link>
            </div>
          )}

          <button
            type="button"
            aria-label={isMobileMenuOpen ? t("header.closeMenu") : t("header.openMenu")}
            onClick={() => setIsMobileMenuOpen((open) => !open)}
            className="ml-1 flex size-9 cursor-pointer items-center justify-center rounded-lg border border-border bg-background text-foreground transition-colors hover:bg-muted md:hidden"
          >
            {isMobileMenuOpen ? (
              <X className="size-4" />
            ) : (
              <Menu className="size-4" />
            )}
          </button>
        </div>
      </div>

      {isMobileMenuOpen && (
        <div className="border-t border-border/80 bg-background px-4 py-3 md:hidden">
          <form
            role="search"
            onSubmit={handleSearch}
            className="relative mb-3 w-full"
          >
            <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3.5 text-muted-foreground">
              <Search className="size-4" />
            </div>
            <Input
              key={searchedFor}
              type="search"
              name="q"
              enterKeyHint="search"
              defaultValue={searchedFor}
              aria-label={t("header.searchLabel")}
              placeholder={t("header.searchShort")}
              className={cn(
                "h-9 w-full rounded-lg border-border/70 bg-muted/40 pr-3 pl-9 text-sm placeholder:text-muted-foreground/70",
                SEARCH_INPUT
              )}
            />
          </form>

          <div className="flex flex-col gap-1">
            {navLinks.map((link) => (
              <Link
                key={link.href}
                to={link.href}
                onClick={() => setIsMobileMenuOpen(false)}
                aria-current={
                  isActiveLink(link.href, currentPath) ? "page" : undefined
                }
                className={`rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
                  isActiveLink(link.href, currentPath)
                    ? "bg-primary/10 text-primary"
                    : "text-foreground hover:bg-muted"
                }`}
              >
                {t(link.label)}
              </Link>
            ))}
          </div>
        </div>
      )}
    </header>
  )
}
