#!/usr/bin/env bash
# One philosophical quote, texted to the owner. SCHED-212's shell body.
#
# WHY THIS IS A SHELL SCRIPT AND NOT A WORKER PROMPT (AMUX-4579).
#
# SCHED-212 was a `tmux` schedule pointed at `self`, and it had been refused on
# every fire since 2026-09-11: `self` is an isolated (raw-agent) worker, so amux
# automation is not delivered into it. Two other fixes were on the table and
# both asked something that is not amux's to change — un-isolating `self` is an
# explicit owner setting, and exempting the schedule from the 30% background
# reserve is the owner's own policy. A `shell` schedule needs neither: `deliver`
# checks `kind == "shell"` before the reserve gate and runs bash instead of
# delivering into a lane (scheduler.rs), so both refusals go away by removing
# the dependency rather than overriding anything.
#
# NO MODEL CALL, DELIBERATELY, AND THIS IS THE LOAD-BEARING PART.
#
# The `claude` CLI is on this box and calling it here would compose a tailored
# quote, which is what the original prompt asked for. It would also spend the
# owner's plan window from inside the one code path that is EXEMPT from the
# reserve protecting that window — and the exemption's own justification, in
# the line above the check, is "a shell schedule wakes no model turn, so it
# consumes none of the plan window the reserve protects". Taking that exemption
# while violating its stated reason is the rejected option (c) through the back
# door, done quietly. So this selects from a fixed set and costs nothing.
#
# WHAT IS LOST, said plainly rather than papered over: the original asked for a
# quote "tailored to him", and `self` is the only composer that knows him. This
# is a rotation, not a tailoring. It is the ritual running at zero cost against
# a week of silence, and un-isolating `self` remains available if the tailoring
# is worth more than the isolation.
set -uo pipefail

PHONE="${AMUX_OWNER_PHONE:-}"
if [ -z "$PHONE" ]; then
  echo "daily-philosophy: AMUX_OWNER_PHONE is not set; nothing to text" >&2
  exit 2
fi

# Tried-and-true, in the sense the request asked for: lines that have been sat
# with for a long time. Kept here rather than in a data file so the schedule
# body is one reviewable artifact.
QUOTES=(
"You have power over your mind — not outside events. Realize this, and you will find strength.  — Marcus Aurelius"
"The unexamined life is not worth living.  — Socrates"
"We suffer more often in imagination than in reality.  — Seneca"
"He who has a why to live can bear almost any how.  — Nietzsche"
"Man is condemned to be free; because once thrown into the world, he is responsible for everything he does.  — Sartre"
"The obstacle is the way.  — Marcus Aurelius"
"It is not that we have a short time to live, but that we waste a lot of it.  — Seneca"
"Everything we hear is an opinion, not a fact. Everything we see is a perspective, not the truth.  — Marcus Aurelius"
"Freedom is secured not by the fulfilling of one's desires, but by the removal of desire.  — Epictetus"
"The impediment to action advances action. What stands in the way becomes the way.  — Marcus Aurelius"
"No man ever steps in the same river twice, for it is not the same river and he is not the same man.  — Heraclitus"
"What we do now echoes in eternity.  — Marcus Aurelius"
"Wealth consists not in having great possessions, but in having few wants.  — Epictetus"
"The greatest remedy for anger is delay.  — Seneca"
"He who fears death will never do anything worthy of a living man.  — Seneca"
"You could leave life right now. Let that determine what you do and say and think.  — Marcus Aurelius"
"Waste no more time arguing what a good man should be. Be one.  — Marcus Aurelius"
"Difficulties strengthen the mind, as labor does the body.  — Seneca"
"It is the power of the mind to be unconquerable.  — Seneca"
"First say to yourself what you would be; and then do what you have to do.  — Epictetus"
"The happiness of your life depends upon the quality of your thoughts.  — Marcus Aurelius"
"Begin at once to live, and count each separate day as a separate life.  — Seneca"
"Whatever is well said by anyone belongs to me.  — Seneca"
"Receive without pride, let go without attachment.  — Marcus Aurelius"
)

# Deterministic but non-repeating: day of year advances the pair, and the two
# daily fires differ. 24 quotes over two slots a day cycles in twelve days.
DOY=$(date +%j | sed 's/^0*//')
SLOT=$([ "$(date +%H)" -lt 12 ] && echo 0 || echo 1)
IDX=$(( (DOY * 2 + SLOT) % ${#QUOTES[@]} ))
MSG="${QUOTES[$IDX]}"

# The EXACT argv `api::alerts` uses for the iMessage leg, which delivered as
# recently as 2026-09-17 (`owner_alerts.channels` -> {"sms":"imessage"}). Args
# are passed after `--` rather than interpolated, so a quote containing a quote
# cannot break the script.
if ! osascript \
  -e 'on run {msg, ph}' \
  -e 'tell application "Messages"' \
  -e 'set s to first service whose service type = iMessage' \
  -e 'set b to buddy ph of s' \
  -e 'send msg to b' \
  -e 'end tell' \
  -e 'end run' \
  -- "$MSG" "$PHONE" >/dev/null 2>/tmp/daily-philosophy.err
then
  # LOUD. A refused or failed fire has to land in schedule_runs as a failure,
  # or this repeats the thing AMUX-4578 is about: a schedule that stops working
  # and says nothing for a week.
  echo "daily-philosophy: iMessage send FAILED: $(head -c 300 /tmp/daily-philosophy.err)" >&2
  exit 1
fi
echo "daily-philosophy: texted quote $IDX"
