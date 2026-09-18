# What amux is actually for, and what isn't that

Ethan, 2026-09-18: "i feel like we need to clean up amux significantly,
theres a lot of latency a lot of moving pieces etc. it needs to be more
KISS, can you capture what you believe are the core functionalities of
amux as well as mapping to what users aim to accomplish with it and then
determine what is irrelevant."

This is a report and a recommendation, not an action — deciding what to cut
is yours to make (ethos rule 8), and several of the calls below need
usage data or a decision only you have. Everything here is measured
against something checkable: a real API family, a real traffic number, or
a real session of lived use, not vibes.

**What I did NOT do:** delete, disable, or gut anything. This is pure
analysis. Cutting is a separate, much bigger, much more reversible-risk
decision, and it's the next thing to decide, not something I did on the
strength of one document.

## Method

- Enumerated every `crates/amux-server/src/api/*.rs` module (97) and every
  `runtime_jobs/*.rs` background job (33) by its own doc comment — not
  guessed, read.
- Pulled real production traffic: `GET /api/logs/stats?since_h=24`,
  measured, 316,681 requests considered, 158,341 in the 24h window,
  53 route families.
- Cross-checked against `~/.claude/CLAUDE.md`'s own already-declared
  primitives list ("board, workers, schedulers, filesystem, groups,
  memories, environment, messages... If a request decomposes into these,
  the work is configuration and UX. Do not add a ninth thing that
  re-expresses them") — this document did not invent a new definition of
  core, it applied amux's own existing one.
- Cross-checked against one very long, very varied lived session (this
  one): fleet health investigation, board/dependency policy work, a
  security-finding chase, worker isolation hardening, a git-worktree bug,
  a dashboard UI fix, screen capture, file-viewer path resolution. Which
  primitives did that actually touch, and which of the 97 modules never
  came up once.

## The core loop, in one paragraph

You run many AI coding/ops agents in parallel, each with its own
terminal, its own repo, its own task. amux's job is to make that
survivable: give each agent a durable identity (**workers/sessions**), a
shared, gated ledger of what's being worked on so nobody has to watch
every terminal (**board**), a way to talk to an agent without babysitting
its pane (**messages**), a way to make routine things happen without you
remembering to trigger them (**schedulers**), a place agents keep context
across restarts (**memories**), a way to configure many agents at once
without hand-editing each one (**environment**), logical grouping so "all
GTM lanes" or "all Mixpeek platform lanes" is one concept
(**groups**), and access to files without a separate tool
(**filesystem**). Everything else is either UX on top of those eight
things, or something else entirely.

## Core functionality → what you're actually trying to accomplish

| Primitive | Your actual goal | Where it lives | Health (measured) |
|---|---|---|---|
| **Workers/sessions** | Run N agents in parallel, know which are alive, start/stop/resume one on demand | `session_verbs`, `sessions_legacy`, `worker_create`, `workers` | `/api/sessions`: 33,963 req/24h, **p50 87ms, p95 1.37s, max 127.7s**. This is the single most-hit family with a real latency problem — see "Where the latency actually is" below. |
| **Board** | A shared ledger of what every agent did/is doing/should do next, with gates so "done" means something | `board`, `board_intake`, `board_lifecycle`, `board_themes`, `criteria`, `commit_mentions`, `deleted_substrate` | `/api/board`: 6,089 req/24h, p50 4ms, **p95 2.99s, max 107.6s**. Fast at the median, real tail latency. |
| **Messages** | Talk to an agent, get a receipt that it actually landed | `messages`, `channels`, `saved_messages`, `history`, `history_ask` | `/api/interactions` (receipts): 105,178 req/24h — **66% of ALL traffic in the fleet**, but fast (p50 0.25ms). This is the "a lot of moving pieces" feeling made concrete: not slow, just extremely chatty. |
| **Schedulers** | Routine work happens without you remembering | `schedules` (API) + `scheduler` (runtime job) | 226 req/24h, p50 6ms. Healthy. |
| **Memories** | An agent doesn't start from zero every session | `memories` | Not in top 20 by volume or latency. Healthy, low-cost. |
| **Environment** | Configure many workers at once, not one at a time | `env_config`, `settings`, `scope`, `prefs` | `env_config`'s own doc calls it "Ethan's centerpiece" — this is core by your own naming, not mine. |
| **Groups** | "All GTM lanes," "all Mixpeek platform lanes" as one concept | `groups` | Small, cheap, load-bearing for the fleet table every session (including this one) reads. |
| **Filesystem** | Read/edit files without leaving the dashboard | `fs`, `files`, `file_viewer`, `upload` | `/api/file`: 34 req/24h, p50 23ms. Low volume, healthy. This is also the surface I fixed twice this session (AMUX-4661, AMUX-4682) — genuinely used, genuinely still has rough edges. |

Everything in this table is core. It's also almost the whole reason for
the traffic and latency you're feeling — the two heaviest hitters by
volume (**interactions**, **sessions**) and by tail latency
(**sessions**, **board**, **git**) are ALL core primitives, not bloat.
**Simplifying amux will not come from deleting features you don't use.
It will come from making the core loop itself cheaper.** See the next
two sections.

## Where the latency actually is (measured, not guessed)

From `/api/logs/stats?since_h=24`, sorted by what actually hurts:

| Family | Calls/24h | p50 | p95 | max | Why (from source, not inference) |
|---|---|---|---|---|---|
| `/api/sessions` | 33,963 | 87ms | 1.37s | **127.7s** | Falls back to a live **tmux pane scrape across the whole fleet** when a worker hasn't self-reported (documented deviation D1 in `.claude/rules/ethos.md`, "mitigated" not "fixed": report endpoint outranks scrape, scrape is the fallback for hookless/crashed lanes — and a busy tmux server makes slow requests arrive in *bursts*, per the file's own comments). |
| `/api/board` | 6,089 | 4ms | 2.99s | 107.6s | Fast at the median; the tail is almost certainly the same fleet-wide-scan shape (`?all=1` reads, gate resolution across type/session/group/column layers). |
| `/api/git` | 3,337 | **869ms** | 3.28s | 7.8s | This is the staged-guard hook — median 869ms means it is **never fast**, every commit on this shared checkout pays it. |
| `/api/workers` | 62 | 1.17s | 3.27s | 8.5s | Low volume but **19.35% error rate** — worth a direct look independent of this document. |
| `/api/browser` | 480 | 20ms | 3.26s | 37.4s | Real browser automation is inherently slow; the tail here is expected, not a red flag. |
| `/api/usage` | 31 | 329ms | 5.5s | 5.6s | Low volume, consistently slow — likely a provider-API round trip, not a bug. |

The two structural, fixable-in-principle costs: **the tmux-scrape fallback
on `/api/sessions`** (a 45+-worker fleet makes this expensive by
construction, and it's already a *known, named, partially-mitigated*
deviation — not new), and **the staged-guard's ~870ms floor on every
git operation** (a real, measured tax on every single commit, paid by
every lane, every time).

## What's core, by count: 97 API modules, 33 background jobs

That count is itself the "a lot of moving pieces" feeling, independent
of any single one being slow. For scale: the 8 primitives above map to
roughly **24** of the 97 API modules. The other ~73 are not bloat by
default — some are genuinely load-bearing infrastructure (auth, health,
sse, sync, static file serving, the python/rust boundary registry) — but
a large fraction are **personal-assistant features bolted onto a fleet
orchestrator**, most of which never came up once in this entire session
despite it covering an unusually wide range of real work:

**Never touched, this session or in the traffic data (0 or near-0 volume
in the last 24h):** `email` / `email_approval` / `email_intel` / `gmail`
/ `gmail_auth`, `calendar`, `crm`, `telegram` (API) + `telegram_poll` /
`telegram_relay` (jobs), `dictation`, `tts`, `torrents`, `habits`,
`journal`, `map`, `brex` (disabled by default per its own doc), `google_sa`,
`recordings` + `recordings_transcribe`, `tunnel` (API) + `tunnel` (job),
`sql`, `terminal` (web-terminal panes — distinct from the session
terminal you actually use), `skin`, `layout_presets`, `branding`,
`speedtest`, `connectors`, `proxies`, `mcp` (as a standalone tab, not the
protocol itself, which other tools use directly), `orchestrate` (the
*voice* fleet-orchestrator, not to be confused with the fan-out
orchestration I fixed today), `graph`, `reclaim`, `grants` (868 calls
but 0 in this session — worth checking who's actually calling it),
`google_sa`.

**Why this matters for "irrelevant," precisely:** none of these are
*broken*. Several are well-built (tts's own doc literally says "the
read-aloud backend the SPA has been calling into a void" — i.e. it was
built because the SPA already called it, not the other way around,
which is its own small case study in scope creep). The question isn't
"does this work," it's **rule 1 from your own ethos.md: "who receives
this by default, without opting in?"** Every one of these ships to every
worker, is compiled into every build, is a route the boundary registry
and route census both have to track (I fixed exactly that bookkeeping
tax twice this session — once for my own `/api/screen`, once discovering
someone else already had to fix it for the fan-out feature), and is
surface area a security review, a new contributor, or a "why is this
slow" investigation like this one has to read past to find the 8 things
that actually run the fleet.

## Concrete recommendation

Not "delete everything above" — that's a sweep, and it's not mine to
make. Three things that ARE concrete and checkable, in order of
confidence:

1. **Measure real usage before cutting anything.** This document used 24h
   of traffic and one long session. That's real evidence, not
   exhaustive evidence — `grants` at 868 calls/24h with zero involvement
   in anything I did is a specific, checkable thing to look at (who's
   calling it, is it a real user or a stray poller), not a reason to
   remove it blind. The same "measure the population, not the vibe" rule
   that's stamped on every diagnostic endpoint in this codebase applies
   to this decision too.
2. **The two real, structural latency costs are worth fixing on their
   own, regardless of what happens to the personal-assistant modules**:
   the `/api/sessions` tmux-scrape fallback (already a named, tracked
   deviation — worth checking how often the fallback actually fires
   versus the report-endpoint fast path it's supposed to be a fallback
   *from*) and the staged-guard's ~870ms floor on every git operation
   (a tax paid on every commit by every lane, all day, forever).
3. **For the "never touched" list**: the honest next step is naming
   which of those you actually still want (some, like calendar/email,
   are probably genuinely used by YOU even if not by me this session —
   I don't have your usage data, only mine), and archiving the rest
   behind a build flag or a slower migration path rather than a single
   delete — several of these (gmail_auth, google_sa, connectors) are
   OAuth/credential plumbing other features may quietly depend on, and
   that's exactly the kind of hidden-dependent risk ethos rule 8 exists
   to slow down.

I can pull the SAME traffic-stats query over a longer window (7d, 30d)
if 24h feels too short to trust, or build a small one-time report that
cross-references board/message history per-module the way I did for
this session by hand, if you want that instead of asking me to guess
from one day.
