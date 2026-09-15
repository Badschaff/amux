#!/bin/bash
# mac-cleanup-tick.sh — the scheduled machine-cleanup tick.
#
# WHAT IT ACTS ON, and it is a short list on purpose:
#   1. `purge`, when the kernel says the machine is under memory pressure or
#      free memory is under a floor. On 2026-09-15 at 10:00 one purge took free
#      memory from 3.6 GB to 14.0 GB. It drops caches; it cannot lose work.
#   2. A launchd agent named in AMUX_CLEANUP_AGENTS whose footprint has grown
#      past AMUX_CLEANUP_AGENT_LEAK_GB. The prompting case is
#      com.procwarden.menubar, which leaked to 27 GB over 15 days and again to
#      1.3 GB within 13 hours of a restart. KeepAlive brings it straight back,
#      so a restart costs nothing but the leak.
#
# WHAT IT ONLY REPORTS, however large it gets:
#   Everything else. fseventsd held 96 GB on this box and macOS protects it; a
#   peer lane's colima VM held 16 GB plus 31 GB compressed and that lane was
#   using it; Chrome and Docker are the human's. Killing another party's work to
#   reclaim memory is a decision for its owner (ethos rule 8), so this names the
#   consumer, its owner and the remedy, and stops there.
#
# WHY sudo appears at all: on this box passwordless sudo is limited to
# /usr/sbin/purge and /usr/bin/mdutil. `purge` is therefore the ONE reclaim this
# script can perform as root, and a reboot (the only remedy for fseventsd) needs
# a password nobody can type for it.
#
# Usage:
#   scripts/mac-cleanup-tick.sh             # measure, act where warranted
#   scripts/mac-cleanup-tick.sh --dry-run   # measure, act on nothing
set -uo pipefail

# launchd's PATH has no /usr/sbin, and sysctl/purge/vm_stat live there. Its
# sibling mac-pressure-tripwire.sh reported measured=false for exactly this
# reason (AMUX-4661), so this one exports the PATH before any probe runs.
PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done

# ── knobs ────────────────────────────────────────────────────────────────────
# Pressure >= this purges. 2 is the kernel's "warn"; it self-clears often, which
# is why the PAGING tripwire ignores 2 and this one does not: dropping caches is
# free, so acting early is cheap and acting late is not.
PRESSURE_PURGE=${AMUX_CLEANUP_PRESSURE_PURGE:-2}
FREE_FLOOR_GB=${AMUX_CLEANUP_FREE_FLOOR_GB:-4}
AGENT_LEAK_GB=${AMUX_CLEANUP_AGENT_LEAK_GB:-2}
AGENTS=${AMUX_CLEANUP_AGENTS:-com.procwarden.menubar}
REPORT_GB=${AMUX_CLEANUP_REPORT_GB:-10}
FSEVENTSD_REBOOT_GB=${AMUX_CLEANUP_FSEVENTSD_REBOOT_GB:-20}
# Seams: the tests point these at a recorder so an action can be observed
# without running it. Defaults are what the scheduler actually runs.
PURGE_CMD=${AMUX_CLEANUP_PURGE_CMD:-sudo -n /usr/sbin/purge}
RESTART_CMD=${AMUX_CLEANUP_RESTART_CMD:-launchctl kickstart -k gui/UID/LABEL}

# ── pure decisions (no side effects, so the tests can exercise them) ──────────

# Purge when the kernel reports pressure at or above the trigger, OR free memory
# is under the floor. Two triggers because either alone misses a real case: a
# machine can sit at pressure 1 with free memory near zero, and it can report
# pressure 2 with free memory that looks fine.
should_purge() { # <pressure_level> <free_gb> <pressure_trigger> <free_floor>
  awk -v p="$1" -v f="$2" -v pt="$3" -v ff="$4" \
    'BEGIN{ exit !((p+0 >= pt+0 && p+0 > 0) || f+0 < ff+0) }'
}

should_restart_agent() { # <footprint_gb> <leak_gb>
  awk -v f="$1" -v t="$2" 'BEGIN{ exit !(f+0 >= t+0 && t+0 > 0) }'
}

# A label this script may hand to launchctl. Anything else is refused rather
# than interpolated into a command line.
is_safe_label() { # <label>
  case "$1" in
    *[!A-Za-z0-9._-]*) return 1 ;;
    com.*) return 0 ;;
    *) return 1 ;;
  esac
}

# Who owns a process, so the report says who can act on it rather than leaving
# a reader to guess. Deliberately coarse: the three answers differ in WHO acts.
classify_owner() { # <user> <command>
  case "$2" in
    *llama-server*|*/Ollama.app/*)
      # Named specially because the remedy is one command and nobody guesses it
      # from "user process": Ollama held qwen3-coder:30b at a 256k context for
      # 54 GB on 2026-09-15, and it unloads on its own keep_alive anyway.
      echo "ollama model server (unload now: ollama stop <model>; it also unloads when idle)" ;;
    */private/tmp/claude-501/*)
      p=${2#*/private/tmp/claude-501/}; p=${p%%/*}
      echo "lane scratch (${p})" ;;
    /System/*|/usr/libexec/*|/usr/sbin/*)
      echo "macOS daemon (SIP-protected, reboot only)" ;;
    *)
      if [ "$1" = "root" ]; then echo "root process"; else echo "user process"; fi ;;
  esac
}

needs_reboot() { # <fseventsd_gb> <threshold>
  awk -v f="$1" -v t="$2" 'BEGIN{ exit !(f+0 >= t+0) }'
}

# Footprint strings from `top` ("1296M", "27G", "512K") into GB.
to_gb() { # <top-mem-string>
  awk -v v="$1" 'BEGIN{
    u=substr(v,length(v)); n=v+0;
    if (u=="G") printf "%.2f", n;
    else if (u=="M") printf "%.2f", n/1024;
    else if (u=="K") printf "%.4f", n/1048576;
    else printf "%.2f", n/1073741824;
  }'
}

# Library mode: the test sources this file for the functions above and must not
# trip a single probe or action doing it.
[ "${AMUX_CLEANUP_LIB_ONLY:-0}" = "1" ] && return 0 2>/dev/null

# ── measure ──────────────────────────────────────────────────────────────────
measured=true
level=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)
case "$level" in ''|*[!0-9]*) level=-1; measured=false ;; esac
read -r free_gb inactive_gb compressor_gb <<EOF
$(vm_stat 2>/dev/null | awk '
  NR==1{ match($0,/[0-9]+ bytes/); ps=substr($0,RSTART,RLENGTH)+0 }
  /Pages free/{f=$3} /Pages inactive/{i=$3} /occupied by compressor/{c=$5}
  END{ gsub(/\./,"",f); gsub(/\./,"",i); gsub(/\./,"",c);
       printf "%.2f %.2f %.2f", f*ps/2^30, i*ps/2^30, c*ps/2^30 }')
EOF
[ -n "${free_gb:-}" ] || { free_gb=-1; inactive_gb=-1; compressor_gb=-1; measured=false; }
swap_line=$(sysctl -n vm.swapusage 2>/dev/null)
swap_used=$(printf '%s' "$swap_line" | sed -E 's/.*used = ([0-9.]+)M.*/\1/'); case "$swap_used" in ''|*[!0-9.]*) swap_used=-1 ;; esac
swap_free=$(printf '%s' "$swap_line" | sed -E 's/.*free = ([0-9.]+)M.*/\1/'); case "$swap_free" in ''|*[!0-9.]*) swap_free=-1 ;; esac

echo "mac-cleanup: measured=$measured pressure=$level free=${free_gb}G inactive=${inactive_gb}G compressor=${compressor_gb}G swap_used=${swap_used}MB swap_free=${swap_free}MB dry_run=$DRY"

# ── act: purge ───────────────────────────────────────────────────────────────
purged=no
if [ "$measured" = true ] && should_purge "$level" "$free_gb" "$PRESSURE_PURGE" "$FREE_FLOOR_GB"; then
  if [ "$DRY" = "1" ]; then
    purged="would (dry run)"
  else
    if $PURGE_CMD >/dev/null 2>&1; then
      sleep 3
      after=$(vm_stat 2>/dev/null | awk '
        NR==1{ match($0,/[0-9]+ bytes/); ps=substr($0,RSTART,RLENGTH)+0 }
        /Pages free/{f=$3} END{ gsub(/\./,"",f); printf "%.2f", f*ps/2^30 }')
      purged="yes (free ${free_gb}G -> ${after}G)"
    else
      # Passwordless sudo is limited to purge and mdutil here; anything else
      # means the grant changed, and saying so beats a silent no-op.
      purged="FAILED (is passwordless sudo for /usr/sbin/purge still granted?)"
    fi
  fi
else
  purged="not needed (trigger: pressure >= $PRESSURE_PURGE or free < ${FREE_FLOOR_GB}G)"
fi
echo "mac-cleanup: purge $purged"

# ── act: restart leaked agents named in the knob ─────────────────────────────
agents_restarted=0; agents_checked=0
uid=$(id -u)
for label in $AGENTS; do
  is_safe_label "$label" || { echo "mac-cleanup: refused agent label '$label' (not a plain com.* label)"; continue; }
  pid=$(launchctl list 2>/dev/null | awk -v l="$label" '$3==l {print $1}')
  case "$pid" in ''|*[!0-9]*) echo "mac-cleanup: agent $label not loaded"; continue ;; esac
  agents_checked=$((agents_checked+1))
  mem=$(top -l 1 -pid "$pid" -stats mem 2>/dev/null | tail -1 | tr -d ' ')
  gb=$(to_gb "${mem:-0}")
  if should_restart_agent "$gb" "$AGENT_LEAK_GB"; then
    if [ "$DRY" = "1" ]; then
      echo "mac-cleanup: agent $label at ${gb}G would be restarted (floor ${AGENT_LEAK_GB}G, dry run)"
    else
      cmd=${RESTART_CMD//UID/$uid}; cmd=${cmd//LABEL/$label}
      if $cmd >/dev/null 2>&1; then
        agents_restarted=$((agents_restarted+1))
        echo "mac-cleanup: agent $label restarted at ${gb}G (floor ${AGENT_LEAK_GB}G)"
      else
        echo "mac-cleanup: agent $label restart FAILED at ${gb}G"
      fi
    fi
  else
    echo "mac-cleanup: agent $label ${gb}G under the ${AGENT_LEAK_GB}G floor, left alone"
  fi
done

# ── report: the consumers this script must not touch ─────────────────────────
# Named with an owner, because the useful half of a hog report is who can act.
echo "mac-cleanup: consumers above ${REPORT_GB}G (reported, never killed):"
reported=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  pid=$(printf '%s' "$line" | awk '{print $1}'); mem=$(printf '%s' "$line" | awk '{print $2}')
  gb=$(to_gb "$mem")
  awk -v g="$gb" -v t="$REPORT_GB" 'BEGIN{ exit !(g+0 >= t+0) }' || continue
  cmd=$(ps -o command= -p "$pid" 2>/dev/null | cut -c1-80)
  usr=$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ')
  echo "mac-cleanup:   ${gb}G pid=$pid $(classify_owner "$usr" "$cmd") — $(printf '%s' "$cmd" | awk '{print $1}' | sed 's|.*/||')"
  reported=$((reported+1))
done <<EOF
$(top -l 1 -o mem -n 12 -stats pid,mem 2>/dev/null | awk 'f{print} /^PID/{f=1}' | sed 's/\*//')
EOF
[ "$reported" = 0 ] && echo "mac-cleanup:   none"

fse_pid=$(pgrep -x fseventsd 2>/dev/null | head -1)
if [ -n "$fse_pid" ]; then
  fse_gb=$(to_gb "$(top -l 1 -pid "$fse_pid" -stats mem 2>/dev/null | tail -1 | tr -d ' ')")
  if needs_reboot "$fse_gb" "$FSEVENTSD_REBOOT_GB"; then
    echo "mac-cleanup: fseventsd holds ${fse_gb}G and is SIP-protected — a reboot is the only remedy (owner runs: sudo fdesetup authrestart)"
  else
    echo "mac-cleanup: fseventsd ${fse_gb}G, under the ${FSEVENTSD_REBOOT_GB}G reboot threshold"
  fi
fi

echo "mac-cleanup: done purge=${purged%% *} agents_restarted=${agents_restarted}/${agents_checked} reported=${reported}"
exit 0
