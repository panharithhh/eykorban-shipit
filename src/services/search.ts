const MAX_WORDS = 6

/**
 * Builds a PostgREST filter, for use with `.or()`, that matches when every
 * word the person typed appears in at least one of `columns`, ignoring case
 * and order. "aether v2.0" finds "Aether Data Platform v2.0", and "vance alex"
 * finds Alex Vance. Returns null for an empty search, so callers can skip it.
 *
 * Shape: `and(or(title.ilike."*aether*",subtitle.ilike."*aether*"),or(…))`,
 * which `.or()` wraps once more; a one-branch OR is just its branch.
 *
 * Values are double-quoted because `,` `.` `:` and parentheses are filter
 * syntax: unquoted, "v2.0" would be read as a column path. `*` is PostgREST's
 * URL-safe spelling of the LIKE wildcard. Characters that would still break
 * out (quotes, backslashes) or act as wildcards (`%` `_` `*`) are dropped, not
 * escaped; nobody needs them to find a person, a job or a piece of work.
 */
export function matchEveryWord(columns: string[], text: string): string | null {
  const words = text
    .replace(/["\\%_*]/g, " ")
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, MAX_WORDS)

  if (words.length === 0) return null

  const perWord = words.map(
    (word) =>
      `or(${columns.map((column) => `${column}.ilike."*${word}*"`).join(",")})`
  )
  return `and(${perWord.join(",")})`
}
