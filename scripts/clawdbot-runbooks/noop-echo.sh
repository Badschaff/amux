#!/usr/bin/env bash
# Touches nothing. Exists so the poller mechanism itself (claim, run, close
# with evidence, or block on failure) can be exercised without touching real
# infrastructure. args: message=<anything>, fail=1 to exercise the failure path.
set -euo pipefail
echo "noop-echo: message='${CLAWDBOT_ARG_MESSAGE:-<none>}'"
if [ "${CLAWDBOT_ARG_FAIL:-0}" = "1" ]; then
  echo "noop-echo: FAIL requested via args" >&2
  exit 1
fi
echo "noop-echo: ok"
