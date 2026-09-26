import { Link, useSearchParams } from "react-router"
import { AlertTriangle, Search as SearchIcon } from "lucide-react"

import { EmptyState } from "@/components/empty-state"
import { FreelancerCard } from "@/components/freelancer-card"
import { JobCard } from "@/components/job-card"
import { ProjectCard } from "@/components/project-card"
import { Button, buttonVariants } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { useAsyncData } from "@/hooks/use-async-data"
import { cn } from "@/lib/utils"
import { listOpenJobs } from "@/services/jobs"
import { listPublishedWork } from "@/services/portfolio"
import { listPublicFreelancers } from "@/services/profiles"

const WORK_LIMIT = 12

function ResultSection({
  title,
  count,
  children,
}: {
  title: string
  count: number
  children: React.ReactNode
}) {
  return (
    <section className="mt-10 first:mt-0">
      <h2 className="text-lg font-semibold tracking-tight">
        {title}{" "}
        <span className="text-sm font-normal text-muted-foreground">
          {count}
        </span>
      </h2>
      <div className="mt-4">{children}</div>
    </section>
  )
}

/**
 * What the header search box leads to: people by name, open jobs, and
 * published work, for the text in `?q=`. The three lookups run in parallel,
 * and each one filters in Postgres rather than in the browser.
 */
const Search = () => {
  const [searchParams] = useSearchParams()
  const query = (searchParams.get("q") ?? "").trim()

  const { data, error, isLoading, refetch } = useAsyncData(async () => {
    if (!query) return null

    const [people, jobs, work] = await Promise.all([
      listPublicFreelancers(undefined, query),
      listOpenJobs({ query }),
      listPublishedWork({ query, limit: WORK_LIMIT }),
    ])
    return { people, jobs, work }
  }, [query])

  if (!query) {
    return (
      <div className="container mx-auto max-w-5xl px-4 py-16">
        <EmptyState
          icon={SearchIcon}
          title="Search EyKorBan"
          description="Type a person's name, a job, or a piece of work in the search box at the top."
        />
      </div>
    )
  }

  if (isLoading) {
    return (
      <div className="flex min-h-[60svh] items-center justify-center">
        <Spinner className="size-6 text-muted-foreground" />
      </div>
    )
  }

  if (error || !data) {
    return (
      <div className="container mx-auto max-w-5xl px-4 py-16">
        <EmptyState
          icon={AlertTriangle}
          title="Search failed"
          description={error ?? undefined}
          action={
            <Button variant="outline" onClick={refetch}>
              Try again
            </Button>
          }
        />
      </div>
    )
  }

  const people = data.people.filter((creative) => creative.profile)
  const total = people.length + data.jobs.length + data.work.length

  return (
    <div className="container mx-auto max-w-6xl px-4 py-8">
      <h1 className="text-2xl font-bold tracking-tight">
        Results for “{query}”
      </h1>
      <p className="mt-1 text-sm text-muted-foreground">
        {total === 0
          ? "Nothing matched."
          : `${total} ${total === 1 ? "result" : "results"}`}
      </p>

      {total === 0 ? (
        <div className="mt-8">
          <EmptyState
            icon={SearchIcon}
            title={`No people, jobs or work match “${query}”`}
            description="Try a shorter word, or someone's first name."
            action={
              <div className="flex flex-wrap justify-center gap-2">
                <Link
                  to="/hire-creatives"
                  className={cn(buttonVariants({ variant: "outline" }))}
                >
                  Browse creatives
                </Link>
                <Link
                  to="/find-work"
                  className={cn(buttonVariants({ variant: "outline" }))}
                >
                  Browse jobs
                </Link>
              </div>
            }
          />
        </div>
      ) : (
        <div className="mt-8">
          {people.length > 0 && (
            <ResultSection title="People" count={people.length}>
              <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                {people.map((creative) =>
                  creative.profile ? (
                    <FreelancerCard
                      key={creative.user.userId}
                      user={creative.user}
                      profile={creative.profile}
                      works={creative.works}
                    />
                  ) : null
                )}
              </div>
            </ResultSection>
          )}

          {data.jobs.length > 0 && (
            <ResultSection title="Jobs" count={data.jobs.length}>
              <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                {data.jobs.map(({ job }) => (
                  <JobCard key={job.id} job={job} />
                ))}
              </div>
            </ResultSection>
          )}

          {data.work.length > 0 && (
            <ResultSection title="Work" count={data.work.length}>
              <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4">
                {data.work.map(({ card, author }) => (
                  <ProjectCard
                    key={card.id}
                    project={card}
                    authorName={author?.name}
                    authorAvatar={author?.avatarUrl}
                    className="max-w-none"
                  />
                ))}
              </div>
            </ResultSection>
          )}
        </div>
      )}
    </div>
  )
}

export default Search
