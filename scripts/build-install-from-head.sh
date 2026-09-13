#!/usr/bin/env bash
# Build installer Rust binaries from one committed source snapshot. The target
# remains shared; configuration/service paths still refer to the user's checkout.
set -euo pipefail
source_repo="${1:?source checkout required}"
target_dir="${2:?Cargo target directory required}"
artifact_dir="${3:?private artifact directory required}"
audit_dir="${AMUX_HOME:-$HOME/.amux}/logs"
source_commit=unmeasured
stage=source
snapshot_root=
snapshot=
compiler_root=
log() {
  local line
  line="$(date -u '+%Y-%m-%dT%H:%M:%SZ') $* commit=$source_commit"
  printf '%s\n' "$line" >&2
  if ! { mkdir -p "$audit_dir" && printf '%s\n' "$line" >> "$audit_dir/server-install.log"; } 2>/dev/null; then
    printf '%s\n' 'WARN installer_source_audit_unavailable: verdict retained on stderr' >&2
  fi
}
finish() {
  local rc=$?
  trap - EXIT
  if [[ -n "$snapshot" ]]; then
    if ! git -C "$source_repo" worktree remove --force "$snapshot" >/dev/null 2>&1; then
      log 'WARN installer_source_cleanup_failed stage=cleanup'
    fi
  fi
  if [[ -n "$snapshot_root" ]]; then rmdir "$snapshot_root" 2>/dev/null || true; fi
  if [[ -n "$compiler_root" ]]; then rm -rf -- "$compiler_root"; fi
  if [[ "$rc" != 0 ]]; then log "WARN installer_source_failed stage=$stage exit=$rc"; fi
  exit "$rc"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# No fallback to working-tree bytes when Git is absent, unreadable or unborn.
# Resolve HEAD once: another worker moving its branch cannot retarget this build.
resolved_commit="$(git -C "$source_repo" rev-parse --verify 'HEAD^{commit}')"
source_commit="$resolved_commit"
unmerged="$(git -C "$source_repo" ls-files -u)"
if [[ -n "$unmerged" ]]; then
  log 'WARN installer_source_refused reason=unmerged_source measured=true n_considered=1'
  exit 1
fi
source_status="$(git -C "$source_repo" status --porcelain --untracked-files=normal)"
if [[ -n "$source_status" ]]; then
  log 'WARN installer_source_selected measured=true n_considered=1 uncommitted_source_excluded=true'
else
  log 'INFO installer_source_selected measured=true n_considered=1 uncommitted_source_excluded=false'
fi
stage=snapshot
snapshot_root="$(mktemp -d "${TMPDIR:-/tmp}/amux-install-source.XXXXXX")"
snapshot="$snapshot_root/source"
git -C "$source_repo" worktree add --detach "$snapshot" "$source_commit"
[[ "$(git -C "$snapshot" rev-parse HEAD)" == "$source_commit" ]]
[[ -z "$(git -C "$snapshot" status --porcelain --untracked-files=no)" ]]

# rustc writes final link outputs DIRECTLY into this private directory while
# Cargo still holds its dependency/build lock. Never copy release/ after Cargo
# exits: another writer could already have replaced those shared output names.
# This fixed ASCII /tmp prefix also keeps commas out of rustc's --emit grammar.
compiler_root="$(mktemp -d /tmp/amux-install-link.XXXXXX)"
stage=build
for entry in 'amux-server:amux-server' 'amux-cli:amux-rs'; do
  package="${entry%%:*}"
  binary="${entry#*:}"
  (cd "$snapshot" && CARGO_TARGET_DIR="$target_dir" \
    CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-${AMUX_CARGO_JOBS:-2}}" \
    ./scripts/safe-cargo.sh rustc --release --locked --package "$package" --bin "$binary" \
    -- "--emit=link=$compiler_root/$binary")
  [[ -x "$compiler_root/$binary" ]]
done
stage=artifact_capture
mkdir -p "$artifact_dir"
for binary in amux-server amux-rs; do
  [[ ! -e "$artifact_dir/$binary" ]]
  cp "$compiler_root/$binary" "$artifact_dir/$binary"
done
python3 "$source_repo/scripts/install-artifact-manifest.py" record "$artifact_dir" "$source_commit"
log 'INFO installer_source_built measured=true n_considered=1 source=committed_snapshot artifacts=private_compiler_outputs'
