#!/usr/bin/env bash
# Grant ONE IAM role to ONE principal on ONE allow-listed GCS bucket.
#
# args: bucket=gs://mvs-recovery-tubescience,role=roles/storage.legacyBucketReader,member=serviceAccount:x@y.iam.gserviceaccount.com
set -euo pipefail

bucket="${AMUXHELPER_ARG_BUCKET:-}"
role="${AMUXHELPER_ARG_ROLE:-}"
member="${AMUXHELPER_ARG_MEMBER:-}"

[ -n "$bucket" ] || { echo "grant-bucket-role: missing arg 'bucket'" >&2; exit 1; }
[ -n "$role" ]   || { echo "grant-bucket-role: missing arg 'role'" >&2; exit 1; }
[ -n "$member" ] || { echo "grant-bucket-role: missing arg 'member'" >&2; exit 1; }

# Bucket allow-list — same list flip-versioning.sh uses, plus the recovery
# bucket this runbook was actually written for. A new bucket is a reviewed
# line here, never an argument alone.
case "$bucket" in
  gs://mvs-snapshots | gs://mvs-snapshots-tubescience | gs://mvs-recovery-tubescience) : ;;
  *)
    echo "grant-bucket-role: '$bucket' is not on the allow-list" >&2
    exit 1
    ;;
esac

# Role allow-list — READ-ONLY / narrow roles only. Anything that can delete,
# overwrite, or change bucket-level IAM itself does not belong in a runbook
# a card can trigger; that stays a human action.
case "$role" in
  roles/storage.legacyBucketReader | roles/storage.objectViewer | roles/storage.buckets.get) : ;;
  *)
    echo "grant-bucket-role: '$role' is not on the allow-list (read-only roles only)" >&2
    exit 1
    ;;
esac

# Principal must be a service account in this org's project convention, not
# an arbitrary email/group/allUsers — a typo'd or copy-pasted 'member' arg
# must not be able to grant a stranger read access to a production bucket.
case "$member" in
  serviceAccount:*.iam.gserviceaccount.com) : ;;
  *)
    echo "grant-bucket-role: 'member' must be a serviceAccount:...iam.gserviceaccount.com principal, got '$member'" >&2
    exit 1
    ;;
esac

echo "grant-bucket-role: granting $role to $member on $bucket"
gcloud storage buckets add-iam-policy-binding "$bucket" --member="$member" --role="$role"
