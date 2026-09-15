# Where the week's tokens went (AMUX-4572)

Ethan, 2026-09-14: "make sure all token usage is captured/labeled so we can
answer 'where is most of my token usage going'; audit at the most granular
level, not just workers."

Measured 2026-09-15 over the 168 hours to that moment: **133,356 turns,
$76,430**. Every figure below comes from `token_ledger` through the shipped
`/api/usage/attribution` endpoint or direct SQL, and each dimension is followed
by what it cannot currently say.

## The answer, in one line

**94.5% of spend is background — work amux started, not work Ethan asked for.**
Of $76,430, he typed $4,212 of it. The single largest line is amux telling a
lane to advance a card.

## By prompt source

| source | turns | cost | |
|---|---:|---:|---|
| `steer:board-drive` | 35,701 | **$26,755** | amux nudged this lane about a card |
| `session` | 20,958 | $15,485 | a peer lane messaged |
| `steer:task-callback` | 13,256 | $8,804 | a task callback from a peer |
| `steer:board-progress` | 6,633 | $5,435 | a board progress note |
| **`user`** | 8,787 | **$4,212** | **you typed it** |
| `direct` | 30,927 | $4,004 | a steering message |
| `steer:sched` | 4,342 | $2,973 | a schedule fired |
| `steer:steering` | 3,823 | $2,477 | a steering message with no guard |
| `steer:commit-nudge` | 1,291 | $1,844 | the commit nudge |
| `task-callback` | 2,223 | $1,325 | a task callback from a peer |

The board-drive nudge alone costs **6.4x everything Ethan typed**. Peer-to-peer
messaging is the second largest line at $15,485, which is the same population
AMUX-4498 measured as 82% carrying no ask at all.

This dimension only became readable when AMUX-4582 shipped: the `steer:*`
families were previously credited to whatever prompt preceded them, usually a
human's, so background work was being counted as Ethan's.

## By model

| model | turns | cost |
|---|---:|---:|
| claude-opus-5 | 52,912 | $52,203 |
| claude-opus-4-8 | 13,083 | $14,358 |
| claude-sonnet-5 | 12,507 | $2,258 |
| claude-opus-4-6 | 8,993 | $2,208 |
| claude-fable-5-1 | 8,874 | $1,991 |
| claude-fable-5 | 7,819 | $1,679 |
| gpt-6-astra | 23,370 | $1,362 |

Codex models are present at all only because AMUX-4583 shipped: 122,413 codex
turns were invisible to every usage view before it.

## By card — DO NOT QUOTE THIS DIMENSION YET

| card | turns | cost |
|---|---:|---:|
| AMUX-1808 | 30,917 | $4,004 |
| AMUX-2598 | 4,482 | $3,575 |
| (unattributed) | 4,709 | $2,193 |

The top two are not cards that cost anything. They are the two stale
`task_windows` rows AMUX-4581 was filed about: windows opened in July that never
closed, read as `COALESCE(left_doing, now)`, absorbing every later turn on their
lane. $7,579 of this week is sitting on two cards that did no work.

AMUX-4581's fix is merged (88fb68c1) but **these numbers will not correct
themselves**, for two separate reasons:

1. The builder has not yet adopted the commit, so the indexer is still running
   the old attribution.
2. `attribute_tasks` only fills rows where `task = ''`. Rows already stamped
   with a wrong card keep it. Clearing the historical misattribution is a
   deliberate act nobody has performed.

So the by-card bars on the Cost tab are wrong today and will stay wrong for
existing rows after the deploy. New turns will be attributed correctly.

## What this audit still cannot see

- **Gemini: nothing at all.** The adapter declares `reports_usage=false` and
  nothing writes `_amux_turns`, so an entire provider is missing from the
  denominator. Open as AMUX-4679. Every percentage here is "of what is
  captured", not "of what was spent".
- **Codex dollars are not real dollars.** No price entry names the codex models,
  so those rows carry the default rate. That is 2.1% of the week ($1,637 of
  $76,430) at a rate nobody has confirmed, and roughly $5,654 of cumulative cost
  that nobody spent. Open as AMUX-4680, awaiting the real per-million rates from
  Ethan. The indexer says this out loud on every pass rather than letting the
  figure pass as measured.
- **The `direct` and `steer:steering` rows are underlabelled.** 30,927 turns
  costing $4,004 say only "a steering message", with no guard naming who sent
  it. They are background by definition, but not yet attributable to a specific
  mechanism.

## What would change the number

The three largest lines are all amux talking to itself: board-drive nudges
($26,755), peer messages ($15,485) and task callbacks ($10,129 across both
spellings) are **$52,369 of $76,430, or 69%**. Ethan's own prompts are 5.5%.
Any serious reduction in spend is a reduction in how often the harness decides
a lane needs to hear from it.
