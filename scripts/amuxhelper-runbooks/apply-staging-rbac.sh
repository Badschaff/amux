#!/usr/bin/env bash
# Apply the ONE known staging RBAC manifest that unblocks #243 gate (a)
# (MI-4736 / MI-5298). No args on purpose — this runbook does exactly one
# thing to exactly one file to exactly one namespace, so there is nothing
# for a card to parameterize its way out of.
set -euo pipefail

MIXPEEK_REPO="${AMUXHELPER_MIXPEEK_REPO:-$HOME/Dev/mixpeek}"
MANIFEST="$MIXPEEK_REPO/server/infra/gke/staging/15-mvs-stateless-guard-rbac.yaml"
NAMESPACE="mixpeek-staging"

[ -f "$MANIFEST" ] || {
  echo "apply-staging-rbac: manifest not found at $MANIFEST (set AMUXHELPER_MIXPEEK_REPO if the mixpeek checkout lives elsewhere)" >&2
  exit 1
}

# Refuse anything but a staging context by name. Context naming isn't
# perfectly standardized across clusters, so this is a guard, not a proof —
# but a runbook that can silently apply to the wrong cluster because nobody
# checked the current context is worse than one that's occasionally overly
# cautious.
ctx="$(kubectl config current-context 2>&1)" || {
  echo "apply-staging-rbac: kubectl has no current context (not authenticated?): $ctx" >&2
  exit 1
}
case "$ctx" in
  *staging*) : ;;
  *)
    echo "apply-staging-rbac: current kubectl context '$ctx' does not look like staging — refusing" >&2
    exit 1
    ;;
esac

echo "apply-staging-rbac: dry-run against context '$ctx'"
kubectl apply --dry-run=server -f "$MANIFEST" -n "$NAMESPACE"

echo "apply-staging-rbac: applying for real"
kubectl apply -f "$MANIFEST" -n "$NAMESPACE"

echo "apply-staging-rbac: verifying"
kubectl get role mvs-stateless-guard -n "$NAMESPACE"
