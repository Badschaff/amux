#!/usr/bin/env bash
# Tests for claude-scratch-report.sh, against a synthetic tree so every
# classification has a known right answer.
#
# The cell that matters most is no_delete_path: this tool's entire promise is
# that it reports and the owning lane decides, and that promise is a property of
# the SOURCE, not of any run. A test that only checks output would stay green on
# the day somebody adds an --apply.
# -e is required by the AF-561 ratchet: a harness that prints a verdict without
# it reports PASS after calling a helper that does not exist, because bash writes
# "command not found" to stderr and carries on. Verified before and after per
# AF-562, since -e changes behaviour in scripts not written for it: exit 0 and 8
# cells both ways.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SUT="$HERE/claude-scratch-report.sh"
FAIL=0
RAN=0
cell() { # name expected actual
  RAN=$((RAN+1))
  if [ "$2" = "$3" ]; then echo "PASS $1: $3"
  else echo "FAIL $1: expected '$2' got '$3'"; FAIL=$((FAIL+1)); fi
}

T=$(mktemp -d -t csr)
trap 'rm -rf "$T"' EXIT
ROOT="$T/scratch"; PROJS="$T/projects"; SESS="$T/sessions"
mkdir -p "$ROOT" "$PROJS" "$SESS"

# A lane whose CC_DIR encodes to the project dir below, so attribution is
# exercised rather than assumed.
printf 'CC_DIR="/Users/x/Dev/solo"\n' > "$SESS/solo-lane.env"
P=-Users-x-Dev-solo
mkdir -p "$PROJS/$P"

mk() { # conv  transcript_age_days|none  size_mb
  local c=$1 age=$2 mb=$3
  mkdir -p "$ROOT/$P/$c"
  mkfile() { dd if=/dev/zero of="$ROOT/$P/$c/blob" bs=1m count="$mb" 2>/dev/null; }
  mkfile
  if [ "$age" != none ]; then
    printf '{"sessionId":"%s"}\n' "$c" > "$PROJS/$P/$c.jsonl"
    touch -t "$(date -v-"${age}"d +%Y%m%d%H%M)" "$PROJS/$P/$c.jsonl"
  fi
}

# Four conversations, one per class the report can assign.
mk fresh-one 0 12          # transcript today            -> LIVE
mk stale-one 9 8           # transcript silent 9 days    -> DEAD
mk notx-one none 6         # no transcript at all        -> NO-TRANSCRIPT
mk caceffea-c12d-475e-a18e-26729434a5d8 0 4   # owner-held, fresh -> OWNER-HELD

out=$(CLAUDE_SCRATCH_ROOT="$ROOT" CLAUDE_PROJECTS_DIR="$PROJS" AMUX_SESSIONS_DIR="$SESS" \
      bash "$SUT" --tsv --dead-days 3 2>/dev/null)
klass() { awk -F'\t' -v c="$1" '$6 ~ c {print $3; exit}' <<<"$out"; }
reachof() { awk -F'\t' -v c="$1" '$6 ~ c {print $4; exit}' <<<"$out"; }

cell live_is_live       LIVE          "$(klass 'fresh-one')"
cell silent_is_dead     DEAD          "$(klass 'stale-one')"

# THE POSITIVE CONTROL THE CARD ASKS FOR, and the reason this class exists.
# /private/tmp/claude-501/bash-edit-diff holds 134 real directories that never
# had a conversation. A rule keyed on transcript age calls every one of them
# silent, so without this cell the dead arm would happily nominate 1.7 GB of
# live tooling scratch. Unknown liveness must never collapse into DEAD.
cell absent_is_not_dead NO-TRANSCRIPT "$(klass 'notx-one')"

# REACHABILITY IS COMPUTED, NOT PINNED. solo-lane has no tmux pane, so the
# owner cannot be told about these bytes right now and the report must say so.
# The 2026-09-14 list hardcoded two UUIDs as owner-held; both lanes are running
# again as of today, so a pinned rule would still be routing their 58.8 GB to
# Ethan while the owners sat there able to act.
cell down_lane_unreachable UNREACHABLE-lane-down "$(reachof 'fresh-one')"

# Prior escalation is recorded ALONGSIDE live reachability, never instead of it.
cell escalation_is_noted_not_substituted \
     "UNREACHABLE-lane-down,escalated-09-14" "$(reachof 'caceffea')"

# Attribution: a workspace with exactly one lane names it.
cell sole_owner_named   solo-lane     "$(awk -F'\t' '$6 ~ /fresh-one/{print $5; exit}' <<<"$out")"

# A shared workspace must NOT name one lane. Add a second lane on the same dir
# and the answer has to become the candidate list.
printf 'CC_DIR="/Users/x/Dev/solo"\n' > "$SESS/second-lane.env"
out2=$(CLAUDE_SCRATCH_ROOT="$ROOT" CLAUDE_PROJECTS_DIR="$PROJS" AMUX_SESSIONS_DIR="$SESS" \
       bash "$SUT" --tsv --dead-days 3 2>/dev/null)
shared=$(awk -F'\t' '$6 ~ /fresh-one/{print $5; exit}' <<<"$out2")
case "$shared" in
  AMBIGUOUS:2-candidates*) echo "PASS shared_is_ambiguous: $shared" ;;
  *) echo "FAIL shared_is_ambiguous: expected AMBIGUOUS:2-candidates, got '$shared'"; FAIL=$((FAIL+1)) ;;
esac
RAN=$((RAN+1))

# The promise, checked against the source. `--apply`, rm -rf, unlink and
# os.remove must all be absent; this tool has no deletion path by construction.
# `|| true` because ZERO MATCHES IS THE PASSING ANSWER here. Under `set -e`
# with pipefail a grep that finds nothing exits 1 and takes the script with it,
# so the cell that proves this tool has no delete path would never run, and the
# harness would report 7 cells instead of 8 while still saying ALL PASS. That is
# the AF-562 hazard the guard warns about, hit on the first try.
bad=$(grep -nE 'rm -rf|--apply|unlink|os\.remove|shutil\.rmtree' "$SUT" | grep -v '^[0-9]*:#' | wc -l | tr -d ' ' || true)
cell no_delete_path 0 "$bad"

echo
# Counted, not written. A literal here could not disagree with the run, which
# is the failure this repo keeps finding in its own summary lines.
echo "cells run: $RAN  failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "ALL PASS"
