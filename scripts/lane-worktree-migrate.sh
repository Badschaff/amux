#!/bin/bash
# AF-316 part 1 / AF-336. Move ONE fleet lane off the shared checkout onto its
# own `git worktree` — own index, own HEAD, same shared object store — without
# losing whatever uncommitted work that lane currently has in flight.
#
# THE PROBLEM THIS SCRIPT IS SHAPED AROUND, not a generic "add a worktree"
# helper: on the day this runs, the shared checkout almost certainly holds
# uncommitted work belonging to OTHER lanes too (measured live while writing
# this: `crates/amux-server/src/api/grants.rs` modified plus two untracked
# planning files, none of it this session's). A migration that scoops up
# "whatever is dirty" and calls it the migrating lane's is the exact incident
# class this card exists to end (AMUX-2647, DESKT-22, AMUX-2637) — just
# committed by the migration tool instead of by `git add -A`.
#
# So this script refuses to guess, and never migrates anything BUT the paths
# the caller explicitly names (--claim) -- it cannot silently sweep a peer's
# file in, because it never reads "whatever is dirty" as the work list. What
# it DOES enforce: if the shared checkout has any dirty path that was not
# named, it stops and prints it rather than proceeding quietly. Without that,
# a caller who names only SOME of what is dirty (a forgotten file of their
# own, or a peer's WIP they did not notice) gets a silent rc=0 that reads as
# a complete migration and is not — the same shape as AMUX-2647/DESKT-22/
# AMUX-2637, just discovered later instead of caused here.
#
# USAGE
#   scripts/lane-worktree-migrate.sh <lane> [--claim path1,path2,...] \
#       [--dest DIR] [--dry-run] [--force]
#
#   <lane>       matches ~/.amux/sessions/<lane>.env — CC_DIR names the shared
#                checkout this lane currently runs from.
#   --claim      comma-separated paths (relative to CC_DIR) that belong to
#                THIS lane's in-flight work. Omit entirely when the tree is
#                already clean for this lane (the common case: run this
#                between tasks, not mid-edit).
#   --acknowledge-unclaimed  comma-separated paths that are dirty, are NOT
#                this lane's, and are explicitly not being migrated. Must
#                name every unclaimed path exactly, same as --claim -- this
#                is the honest escape hatch past the refusal below, not a
#                silent one.
#   --dest       new worktree path. Default: ~/Dev/amux-lanes/<lane>.
#   --dry-run    print every step without creating the worktree or writing
#                anything outside a scratch temp dir.
#   --force      allow an existing, empty --dest directory.
#
# WHAT IT DOES NOT DO, on purpose:
#   - Does not touch ~/.amux/sessions/<lane>.env. Printed as the manual final
#     step so a human (or the lane itself, once satisfied) makes that switch
#     deliberately, not this script mid-run.
#   - Does not delete or revert anything in the ORIGINAL shared checkout. The
#     claimed paths' bytes are COPIED into the new worktree; the shared
#     checkout keeps its own copy until someone explicitly cleans it up, so a
#     bad migration is a re-run, not a loss.
#   - Does not restart any tmux pane or touch any other lane.
#
# PILOTED LIVE (AF-336 acceptance criterion 1), 2026-09-18: amux-frustrations
# migrated itself to ~/Dev/amux-lanes/amux-frustrations with
# --acknowledge-unclaimed covering two peer files it found dirty and did not
# own, then edited, committed and pushed THIS line from the new worktree --
# the pre-commit/staged-guard/pre-push hooks ran unchanged, resolved via the
# shared checkout's common .git/hooks dir, no CC_DIR flip performed (this
# pilot verifies the mechanism; switching the lane's default checkout over
# permanently is a separate, deliberate step).
set -euo pipefail

lane=""
claim_csv=""
acknowledge_csv=""
dest=""
dry_run=0
force=0

usage() {
  echo "usage: $0 <lane> [--claim p1,p2,...] [--acknowledge-unclaimed p1,p2,...] [--dest DIR] [--dry-run] [--force]" >&2
  exit 2
}

[ $# -ge 1 ] || usage
lane="$1"; shift
case "$lane" in --*) usage ;; esac

while [ $# -gt 0 ]; do
  case "$1" in
    --claim) claim_csv="${2:-}"; shift 2 ;;
    --acknowledge-unclaimed) acknowledge_csv="${2:-}"; shift 2 ;;
    --dest) dest="${2:-}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --force) force=1; shift ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

note() { printf '  %s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }
die()  { printf 'REFUSED: %s\n' "$*" >&2; exit 1; }

env_file="${AMUX_SESSIONS_DIR:-$HOME/.amux/sessions}/$lane.env"
[ -f "$env_file" ] || die "no env file for lane '$lane' at $env_file — is the name right?"

cc_dir="$(sed -n 's/^CC_DIR="\(.*\)"$/\1/p' "$env_file" | head -1)"
[ -n "$cc_dir" ] || die "$env_file has no CC_DIR= line"
[ -d "$cc_dir/.git" ] || die "$cc_dir is not a git checkout root (no .git dir — already a linked worktree, or wrong path)"

git -C "$cc_dir" remote get-url origin >/dev/null 2>&1 || die "$cc_dir has no 'origin' remote"

dest="${dest:-$HOME/Dev/amux-lanes/$lane}"

step "lane '$lane': shared checkout is $cc_dir, target worktree is $dest"

IFS=',' read -r -a claimed <<<"${claim_csv:-}"
# Trim empties from a trailing/leading comma or an entirely empty --claim.
claimed_clean=()
for p in ${claimed[@]+"${claimed[@]}"}; do
  [ -n "$p" ] && claimed_clean+=("$p")
done

IFS=',' read -r -a acked <<<"${acknowledge_csv:-}"
acked_clean=()
for p in ${acked[@]+"${acked[@]}"}; do
  [ -n "$p" ] && acked_clean+=("$p")
done

# ── refuse to guess whose dirt is whose ──────────────────────────────────────
# --acknowledge-unclaimed is the one honest way past this: not a silent
# bypass, a second explicit list. It must name EXACTLY the unclaimed paths --
# same accounting principle as --claim itself -- so a caller cannot wave away
# "whatever else happens to be dirty" today and have it quietly cover a
# DIFFERENT file tomorrow. Anything acknowledged is not snapshotted and not
# touched; it is left exactly where it is, same as everything else in the
# original checkout.
dirty_all="$(git -C "$cc_dir" status --porcelain --untracked-files=all)"
unclaimed=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  path="${line:3}"
  found=0
  for c in ${claimed_clean[@]+"${claimed_clean[@]}"} ${acked_clean[@]+"${acked_clean[@]}"}; do
    [ "$c" = "$path" ] && found=1 && break
  done
  [ "$found" -eq 0 ] && unclaimed="$unclaimed  $line"$'\n'
done <<<"$dirty_all"

if [ -n "$unclaimed" ]; then
  printf 'REFUSED: %s has dirty paths not named in --claim or --acknowledge-unclaimed:\n%s' "$cc_dir" "$unclaimed" >&2
  cat >&2 <<'EOF'
These may belong to another lane working in the same shared checkout right
now (this is the exact hazard AF-336 exists to end). Either:
  - re-run with --claim naming every path above that is genuinely yours, or
  - re-run with --acknowledge-unclaimed naming every path above that is
    genuinely NOT yours and you have verified is safe to leave untouched, or
  - coordinate with whoever owns the rest before migrating, or
  - wait until the tree is clean for you and run this with no --claim at all.
Nothing was written.
EOF
  exit 1
fi
note "every dirty path in $cc_dir accounted for (${#claimed_clean[@]} claimed, ${#acked_clean[@]} acknowledged unclaimed)"

# ── snapshot the claimed paths ───────────────────────────────────────────────
step "snapshotting claimed paths"
snap="$(mktemp -d "${TMPDIR:-/tmp}/af336-migrate.XXXXXX")"
trap 'rm -rf "$snap"' EXIT
tracked_patch="$snap/tracked.patch"
: > "$tracked_patch"
untracked_dir="$snap/untracked"
mkdir -p "$untracked_dir"
have_tracked_patch=0
for p in ${claimed_clean[@]+"${claimed_clean[@]}"}; do
  status="$(git -C "$cc_dir" status --porcelain --untracked-files=all -- "$p" | head -1)"
  case "$status" in
    "??"*)
      mkdir -p "$untracked_dir/$(dirname "$p")"
      cp -p "$cc_dir/$p" "$untracked_dir/$p"
      note "untracked, copied: $p"
      ;;
    "")
      note "claimed but not dirty, skipping: $p"
      ;;
    *)
      git -C "$cc_dir" diff HEAD -- "$p" >> "$tracked_patch"
      have_tracked_patch=1
      note "tracked change, diffed: $p"
      ;;
  esac
done

if [ "$dry_run" -eq 1 ]; then
  step "dry run — stopping before any worktree is created"
  note "would create: $dest"
  note "tracked patch bytes: $(wc -c < "$tracked_patch" | tr -d ' ')"
  note "untracked files staged: $(find "$untracked_dir" -type f | wc -l | tr -d ' ')"
  exit 0
fi

# ── create the new worktree ──────────────────────────────────────────────────
step "creating worktree at $dest"
if [ -e "$dest" ]; then
  if [ "$force" -eq 1 ] && [ -d "$dest" ] && [ -z "$(ls -A "$dest")" ]; then
    rmdir "$dest"
  else
    die "$dest already exists (pass --force if it is an empty directory you meant)"
  fi
fi
mkdir -p "$(dirname "$dest")"
git -C "$cc_dir" fetch origin --quiet
# DETACHED, matching the pattern already proven all through this fleet's own
# scratch worktrees: a live branch checkout (`git worktree add <path> main`)
# fails with "branch already checked out" while the shared tree still holds
# main, and every lane pushes with `git push origin HEAD:main` regardless, so
# a local branch pointer buys nothing here.
git -C "$cc_dir" worktree add --detach "$dest" origin/main

# ── reapply the claim ────────────────────────────────────────────────────────
step "reapplying claimed work onto the new worktree"
if [ "$have_tracked_patch" -eq 1 ] && [ -s "$tracked_patch" ]; then
  git -C "$dest" apply "$tracked_patch"
  note "tracked patch applied"
fi
if [ -n "$(find "$untracked_dir" -type f 2>/dev/null)" ]; then
  cp -pR "$untracked_dir/." "$dest/"
  note "untracked files copied"
fi

# ── verify: the new worktree's dirt is EXACTLY the claim, nothing more, ─────
# nothing less. This is the correctness check, not a formality — a silent
# partial-apply would be worse than the refusal above, because it would look
# like success.
step "verifying"
new_dirty="$(git -C "$dest" status --porcelain --untracked-files=all | awk '{print $2}' | sort)"
want_dirty="$(printf '%s\n' "${claimed_clean[@]:-}" | sed '/^$/d' | sort)"
if [ "$new_dirty" != "$want_dirty" ]; then
  cat >&2 <<EOF
VERIFICATION FAILED: the new worktree's dirty paths do not match the claim.
  claimed:
$(printf '    %s\n' "${claimed_clean[@]:-}")
  actually dirty in $dest:
$(printf '%s\n' "$new_dirty" | sed 's/^/    /')
The original checkout at $cc_dir is UNTOUCHED — nothing was lost there. The
new worktree at $dest is left in place for inspection; delete it by hand
(git -C "$cc_dir" worktree remove "$dest" --force) before retrying.
EOF
  exit 1
fi
note "new worktree's dirty set matches the claim exactly"

# hooks: install-hooks.sh writes into the COMMON .git/hooks dir shared by
# every worktree of this repo (scripts/test-install-hooks-worktree.sh pins
# this), so nothing needs installing here — just confirm the new worktree
# actually resolves to that common dir rather than inventing its own.
# `rev-parse --git-common-dir` can print a path RELATIVE TO THE REPO, not to
# this script's own cwd, so join it against the repo dir before treating it as
# a path — cd'ing straight into the raw output failed exactly this way the
# first time this was tested (relative ".git/hooks", cwd elsewhere: "No such
# file or directory").
git_common_hooks_dir() {
  local repo="$1" raw
  raw="$(cd "$repo" && git rev-parse --git-common-dir)"
  case "$raw" in
    /*) printf '%s/hooks\n' "$raw" ;;
    *) printf '%s/%s/hooks\n' "$repo" "$raw" ;;
  esac
}
common_hooks_shared="$(git_common_hooks_dir "$cc_dir")"
common_hooks_new="$(git_common_hooks_dir "$dest")"
if [ "$(cd "$common_hooks_shared" && pwd -P)" != "$(cd "$common_hooks_new" && pwd -P)" ]; then
  cat >&2 <<EOF
VERIFICATION FAILED: the new worktree resolves a DIFFERENT hooks dir than the
shared checkout ($common_hooks_new vs $common_hooks_shared) — hooks installed
today would not apply there. Not cleaning up automatically; investigate before
switching this lane over.
EOF
  exit 1
fi
note "hooks: new worktree shares the same installed hooks dir ($common_hooks_new)"

step "done"
cat <<EOF
New worktree ready: $dest
The original checkout at $cc_dir was NOT modified — the claimed paths are
still dirty there too, on purpose, until you confirm the new worktree is good.

Remaining manual steps (not run by this script):
  1. Sanity-check the new worktree yourself (cargo check, a test commit+push
     to a throwaway branch, whatever this lane's normal workflow is).
  2. Point the lane at it:
       sed -i '' 's|^CC_DIR=.*|CC_DIR="$dest"|' "$env_file"
  3. Restart this lane's pane so the new CC_DIR takes effect.
  4. ONLY once (2) and (3) are confirmed working, clean up the shared
     checkout's copy of the claimed paths:
       git -C "$cc_dir" checkout -- <tracked claimed paths>
       rm -- <untracked claimed paths>
EOF
