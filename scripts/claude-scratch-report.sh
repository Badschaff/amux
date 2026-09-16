#!/usr/bin/env bash
# Report what /private/tmp/claude-501 is holding, per conversation and per
# owning lane. THIS SCRIPT NEVER DELETES ANYTHING. There is no --apply, and
# there is a test that greps for the absence of a delete path, because the whole
# point is that the lane which owns the bytes decides, not amux (AMUX-4615).
#
# Why this is separate from reap-amux-debris.sh: that reaper deliberately skips
# claude-501 in three places, and it is right to. This is live scratchpad space
# for every running Claude Code session on the machine, so an age-based reaper
# over it moves someone's working files. `reclaim.rs`'s guard refuses the same
# path and says why:
#
#   "Its own top-level mtime can look stale for hours while sessions write deep
#    inside their own subdirs (APFS only bumps a directory's mtime when its
#    direct entries change), so age-based heuristics over it are unreliable in
#    exactly the direction that would move someone's live working files."
#
# So LIVENESS IS NEVER TAKEN FROM A DIRECTORY MTIME here. It comes from the
# conversation's TRANSCRIPT, which is appended on every turn and cannot go
# stale while the session is working.
#
# Usage: scripts/claude-scratch-report.sh [--min-gb N] [--dead-days N] [--tsv]
set -uo pipefail

ROOT=${CLAUDE_SCRATCH_ROOT:-/private/tmp/claude-501}
PROJ=${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}
SESS=${AMUX_SESSIONS_DIR:-$HOME/.amux/sessions}
MIN_GB=1.0        # a subfolder smaller than this is noise, not a finding
DEAD_DAYS=3       # transcript silent this long = the conversation is over
TSV=0

while [ $# -gt 0 ]; do
  case "$1" in
    --min-gb) MIN_GB=$2; shift 2 ;;
    --dead-days) DEAD_DAYS=$2; shift 2 ;;
    --tsv) TSV=1; shift ;;
    -h|--help) sed -n '1,25p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# OWNER-HELD. These two were surfaced to their lanes on 2026-09-14 and could not
# be actioned: mixpeek-ops-server was not running and mixpeek-cicd is paused, so
# both are waiting on Ethan. They are reported for completeness and never
# appear as actionable, so nobody sweeps a scratchpad whose disposition the
# owner still holds.
OWNER_HELD="caceffea-c12d-475e-a18e-26729434a5d8 db837290-839f-4c5a-addc-4aa3c72a4256"

now=$(date +%s)

# Encode each lane's CC_DIR the way Claude Code names a project directory
# (path separators become dashes). ENCODING IS DETERMINISTIC AND DECODING IS
# NOT: `-Users-ethan-Dev-ai-for-smbs` could be /Users/ethan/Dev/ai-for-smbs or
# /Users/ethan/Dev/ai/for/smbs, so the map is built in the direction that has
# one answer.
lane_map=$(
  for f in "$SESS"/*.env; do
    [ -f "$f" ] || continue
    d=$(grep -h '^CC_DIR=' "$f" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "$d" ] || continue
    printf '%s\t%s\n' "$(printf '%s' "${d%/}" | tr '/' '-')" "$(basename "${f%.env}")"
  done | sort
)

running_lanes=$(tmux list-panes -a -F '#{session_name}' 2>/dev/null | sed 's/^amux-//' | sort -u)

# Lanes whose CC_DIR encodes to this project directory. A SHARED WORKSPACE HAS
# NO SINGLE OWNER: /Users/ethan/Dev/mixpeek is the CC_DIR of 19 lanes and
# /Users/ethan/Dev/amux of 10, so for those the honest answer is the candidate
# list, not a pick. Naming one would be a guess that reads like a fact, and
# that is how the 2026-09-14 delivery routed bytes to lanes that could not act.
attribute() {
  local proj=$1 lanes n running=
  lanes=$(awk -F'\t' -v k="$proj" '$1==k{print $2}' <<<"$lane_map")
  n=$(printf '%s' "$lanes" | grep -c . )
  if [ "$n" = 0 ]; then echo "unattributed"; return; fi
  if [ "$n" = 1 ]; then echo "$lanes"; return; fi
  for l in $lanes; do
    grep -qx "$l" <<<"$running_lanes" && running="${running}${running:+,}$l"
  done
  echo "AMBIGUOUS:${n}-candidates${running:+ running=$running}"
}

emit() {  # size_gb  age  class  owner  path
  if [ "$TSV" = 1 ]; then printf '%s\t%s\t%s\t%s\t%s\n' "$@"
  else printf '%-8s %-14s %-13s %-34s %s\n' "$@"; fi
}

[ "$TSV" = 1 ] || emit "SIZE_GB" "TRANSCRIPT" "CLASS" "OWNER" "CONVERSATION"

tot=0; n_conv=0; n_live=0; n_dead=0; n_notx=0; n_held=0
gb_live=0; gb_dead=0; gb_notx=0; gb_held=0
report=$(
for cdir in "$ROOT"/*/*/; do
  [ -d "$cdir" ] || continue
  conv=$(basename "$cdir"); proj=$(basename "$(dirname "$cdir")")
  kb=$(du -sk "$cdir" 2>/dev/null | awk '{print $1}'); [ -n "$kb" ] || continue
  gb=$(awk -v k="$kb" 'BEGIN{printf "%.2f", k/1048576}')

  tx="$PROJ/$proj/$conv.jsonl"
  if [ -f "$tx" ]; then
    mt=$(stat -f %m "$tx" 2>/dev/null || echo 0)
    age=$(awk -v n="$now" -v m="$mt" 'BEGIN{d=(n-m)/86400; printf "%.1f", (d<0?0:d)}')
    if awk -v a="$age" -v d="$DEAD_DAYS" 'BEGIN{exit !(a>=d)}'; then cls=DEAD; else cls=LIVE; fi
    agestr="${age}d"
  else
    # NO TRANSCRIPT IS NOT DEATH. `bash-edit-diff` holds 20+ directories that
    # never had a conversation, so a rule keyed on transcript age marks every
    # one of them reapable. Unknown liveness is its own class and is never
    # actionable.
    cls=NO-TRANSCRIPT; agestr="absent"
  fi
  # An `if`, not a `case`: bash 3.2 (what /bin/bash is on this Mac) mis-parses a
  # case statement nested inside $( ), taking the pattern's `)` as the end of
  # the command substitution.
  if [[ " $OWNER_HELD " == *" $conv "* ]]; then cls=OWNER-HELD; fi

  emit "$gb" "$agestr" "$cls" "$(attribute "$proj")" "$proj/$conv"
done | sort -k1 -rn
)
printf '%s\n' "$report"

# Summary computed from the rows above, never written by hand. Every count
# carries the population it is over.
printf '%s\n' "$report" | awk -v min="$MIN_GB" '
  { g=$1+0; c=$3; tot+=g; n++
    if (c=="LIVE") { L+=g; nl++ } else if (c=="DEAD") { D+=g; nd++ }
    else if (c=="OWNER-HELD") { H+=g; nh++ } else { U+=g; nu++ }
    if (g>=min) { big++ } }
  END {
    printf "\n%d conversation(s), %.1f GB total\n", n, tot
    printf "  LIVE          %5.1f GB over %d  (transcript written recently; not a cleanup target)\n", L, nl
    printf "  DEAD          %5.1f GB over %d  (transcript silent; the only reapable class)\n", D, nd
    printf "  OWNER-HELD    %5.1f GB over %d  (surfaced 09-14, lane could not act; Ethan decides)\n", H, nh
    printf "  NO-TRANSCRIPT %5.1f GB over %d  (liveness unknown; never actionable)\n", U, nu
    printf "  %d of %d conversation(s) are >= %s GB\n", big, n, min
    if (tot>0) printf "  reapable share: %.1f%% of all bytes here\n", 100*D/tot
  }'
