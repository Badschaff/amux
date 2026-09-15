#!/bin/bash
# Safety and decision properties of scripts/mac-cleanup-tick.sh.
#
# The tick runs as root for one command and restarts a launchd agent, so the
# properties worth pinning are the ones that keep it from acting when it should
# not: the thresholds, the label guard, and dry run. Each cell fails if its
# guard is removed — the point is that it CAN go red (ethos rule 7).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TICK="$HERE/mac-cleanup-tick.sh"
FIX=$(mktemp -d)                      # never a fixed name: /tmp is shared
trap 'rm -rf -- "$FIX"' EXIT
fails=0
[ -x "$TICK" ] || { echo "FAIL: $TICK missing or not executable — no cell below ran"; exit 1; }
check() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: expected '$2', got '$3'"; fails=$((fails+1)); fi; }

# Library mode must define the decisions without running a single probe.
AMUX_CLEANUP_LIB_ONLY=1 . "$TICK"
check "library mode defines should_purge" "yes" "$(type should_purge >/dev/null 2>&1 && echo yes || echo no)"

echo "1. purge triggers on either signal, and on neither it stays put"
check "healthy machine is left alone"      "no"  "$(should_purge 1 20 2 4 && echo yes || echo no)"
check "kernel pressure alone triggers"     "yes" "$(should_purge 2 20 2 4 && echo yes || echo no)"
check "low free alone triggers"            "yes" "$(should_purge 1 2 2 4 && echo yes || echo no)"
# -1 is this script's "probe failed" value. Acting on it would purge on every
# tick of a machine whose sysctl is missing, which is the AMUX-4661 shape.
# -1 vs a trigger of -1: without the "pressure was actually measured" guard,
# a failed probe compares equal and purges on every tick. With the default
# trigger of 2 this cell would pass either way, which is a check that cannot
# fail (ethos rule 7).
check "an unmeasured pressure does not trigger by itself" "no" "$(should_purge -1 20 -1 -1 && echo yes || echo no)"
check "a measured pressure at the trigger still fires"    "yes" "$(should_purge 2 20 2 -1 && echo yes || echo no)"

echo "2. an agent is restarted only past the leak floor"
check "small agent left alone" "no"  "$(should_restart_agent 0.05 2 && echo yes || echo no)"
check "leaked agent restarted" "yes" "$(should_restart_agent 2.5 2 && echo yes || echo no)"
check "a zero floor never restarts" "no" "$(should_restart_agent 99 0 && echo yes || echo no)"

echo "3. only a plain com.* label may reach launchctl"
check "ordinary label accepted"   "yes" "$(is_safe_label com.procwarden.menubar && echo yes || echo no)"
check "shell metacharacters refused" "no" "$(is_safe_label 'com.evil;rm -rf /' && echo yes || echo no)"
check "non-com label refused"     "no"  "$(is_safe_label 'evil' && echo yes || echo no)"

echo "4. footprint strings convert to GB"
check "gigabytes" "27.00" "$(to_gb 27G)"
check "megabytes" "1.27"  "$(to_gb 1296M)"
check "kilobytes" "0.0005" "$(to_gb 512K)"

echo "5. the report names who can act"
case "$(classify_owner ethan /private/tmp/claude-501/-Users-ethan-Dev-ai-for-smbs/abc/scratchpad/lima-native/bin/limactl)" in
  *"lane scratch (-Users-ethan-Dev-ai-for-smbs)"*) echo "  ok   a lane's process names its lane" ;;
  *) echo "  FAIL a lane's process is not attributed: $(classify_owner ethan /private/tmp/claude-501/-Users-ethan-Dev-ai-for-smbs/abc/x)"; fails=$((fails+1)) ;;
esac
case "$(classify_owner root /System/Library/Frameworks/Virtualization.framework/x)" in
  *"macOS daemon"*) echo "  ok   a system daemon is named as reboot-only" ;;
  *) echo "  FAIL a system daemon is misattributed"; fails=$((fails+1)) ;;
esac
check "a user's own app" "user process" "$(classify_owner ethan /Applications/Google Chrome.app/Contents/MacOS/Chrome)"
case "$(classify_owner ethan /Applications/Ollama.app/Contents/Resources/llama-server)" in
  *"ollama stop"*) echo "  ok   an ollama model server carries its unload command" ;;
  *) echo "  FAIL an ollama model server is not named with its remedy"; fails=$((fails+1)) ;; esac

echo "6. the reboot line appears only when fseventsd is actually large"
check "small fseventsd asks for no reboot" "no"  "$(needs_reboot 8 20 && echo yes || echo no)"
check "large fseventsd asks for a reboot"  "yes" "$(needs_reboot 96 20 && echo yes || echo no)"

# Cells 7 and 8 drive the real script, whose probes are macOS-only (vm_stat,
# kern.memorystatus_vm_pressure_level). On Linux the tick reports measured=false
# and correctly refuses to act, so these cells would fail for a reason that is
# not a defect. Skipped LOUDLY: a silent skip is how a suite reads green while
# testing nothing.
if [ "$(uname)" != "Darwin" ]; then
  echo "7-8. skipped on $(uname): the end-to-end cells need macOS probes (vm_stat, kern.memorystatus_vm_pressure_level)"
  echo
  if [ "$fails" -eq 0 ]; then echo "PASS: mac-cleanup-tick — decision cells passed; end-to-end cells skipped off macOS"; exit 0; fi
  echo "mac-cleanup-tick: $fails check(s) FAILED"; exit 1
fi

echo "7. end to end: the action runs when triggered, and dry run performs none"
REC="$FIX/purge-calls"
cat > "$FIX/fake-purge.sh" <<EOF
#!/bin/bash
echo called >> "$REC"
EOF
chmod +x "$FIX/fake-purge.sh"
: > "$REC"
# Force the trigger with the free floor so the cell does not depend on the
# machine it runs on being under pressure.
AMUX_CLEANUP_PURGE_CMD="$FIX/fake-purge.sh" AMUX_CLEANUP_FREE_FLOOR_GB=99999 \
  AMUX_CLEANUP_AGENTS="" AMUX_CLEANUP_REPORT_GB=99999 "$TICK" >/dev/null 2>&1
check "purge ran when triggered" "1" "$(wc -l < "$REC" | tr -d ' ')"
: > "$REC"
AMUX_CLEANUP_PURGE_CMD="$FIX/fake-purge.sh" AMUX_CLEANUP_FREE_FLOOR_GB=99999 \
  AMUX_CLEANUP_AGENTS="" AMUX_CLEANUP_REPORT_GB=99999 "$TICK" --dry-run >/dev/null 2>&1
check "dry run performed no purge" "0" "$(wc -l < "$REC" | tr -d ' ')"
: > "$REC"
AMUX_CLEANUP_PURGE_CMD="$FIX/fake-purge.sh" AMUX_CLEANUP_FREE_FLOOR_GB=0 AMUX_CLEANUP_PRESSURE_PURGE=99 \
  AMUX_CLEANUP_AGENTS="" AMUX_CLEANUP_REPORT_GB=99999 "$TICK" >/dev/null 2>&1
check "no purge when neither trigger fires" "0" "$(wc -l < "$REC" | tr -d ' ')"

echo "8. end to end: an agent restart goes through the knob, and only past the floor"
AREC="$FIX/restart-calls"
cat > "$FIX/fake-restart.sh" <<EOF
#!/bin/bash
echo "\$@" >> "$AREC"
EOF
chmod +x "$FIX/fake-restart.sh"
: > "$AREC"
# A label that IS loaded on any Mac, with a 0.0001 GB floor so the footprint
# cannot keep the cell from firing. The positive control is the call itself.
LIVE_LABEL=$(launchctl list 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+$/ && $3 ~ /^com\./ {print $3; exit}')
if [ -n "$LIVE_LABEL" ]; then
  AMUX_CLEANUP_RESTART_CMD="$FIX/fake-restart.sh UID LABEL" AMUX_CLEANUP_AGENTS="$LIVE_LABEL" \
    AMUX_CLEANUP_AGENT_LEAK_GB=0.0001 AMUX_CLEANUP_FREE_FLOOR_GB=0 AMUX_CLEANUP_PRESSURE_PURGE=99 \
    AMUX_CLEANUP_REPORT_GB=99999 "$TICK" >/dev/null 2>&1
  check "leaked agent restart invoked the knob" "1" "$(wc -l < "$AREC" | tr -d ' ')"
  case "$(cat "$AREC")" in *"$LIVE_LABEL"*) echo "  ok   the restart names the agent" ;;
    *) echo "  FAIL the restart did not name the agent: $(cat "$AREC")"; fails=$((fails+1)) ;; esac
  : > "$AREC"
  AMUX_CLEANUP_RESTART_CMD="$FIX/fake-restart.sh UID LABEL" AMUX_CLEANUP_AGENTS="$LIVE_LABEL" \
    AMUX_CLEANUP_AGENT_LEAK_GB=9999 AMUX_CLEANUP_FREE_FLOOR_GB=0 AMUX_CLEANUP_PRESSURE_PURGE=99 \
    AMUX_CLEANUP_REPORT_GB=99999 "$TICK" >/dev/null 2>&1
  check "agent under the floor is left alone" "0" "$(wc -l < "$AREC" | tr -d ' ')"
  : > "$AREC"
  AMUX_CLEANUP_RESTART_CMD="$FIX/fake-restart.sh UID LABEL" AMUX_CLEANUP_AGENTS='com.evil;touch /tmp/pwned' \
    AMUX_CLEANUP_AGENT_LEAK_GB=0.0001 AMUX_CLEANUP_FREE_FLOOR_GB=0 AMUX_CLEANUP_PRESSURE_PURGE=99 \
    AMUX_CLEANUP_REPORT_GB=99999 "$TICK" >/dev/null 2>&1
  check "an unsafe label never reaches the restart" "0" "$(wc -l < "$AREC" | tr -d ' ')"
else
  echo "  FAIL no loaded com.* launchd label found, so cells 8 could not run"
  fails=$((fails+1))
fi

echo
if [ "$fails" -eq 0 ]; then echo "PASS: mac-cleanup-tick — all checks passed"; exit 0; fi
echo "mac-cleanup-tick: $fails check(s) FAILED"; exit 1
