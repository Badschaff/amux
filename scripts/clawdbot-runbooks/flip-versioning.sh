#!/usr/bin/env bash
# Enable GCS object versioning on an allow-listed bucket.
#
# args: bucket=gs://mvs-snapshots
set -euo pipefail

bucket="${CLAWDBOT_ARG_BUCKET:-}"
[ -n "$bucket" ] || { echo "flip-versioning: missing arg 'bucket'" >&2; exit 1; }

# Allow-list, not a denylist: this runbook may only ever touch a bucket it
# was explicitly written for. A new bucket needs a new line here (a
# reviewed change), never an argument alone.
case "$bucket" in
  gs://mvs-snapshots | gs://mvs-snapshots-tubescience) : ;;
  *)
    echo "flip-versioning: '$bucket' is not on the allow-list (mvs-snapshots, mvs-snapshots-tubescience)" >&2
    exit 1
    ;;
esac

echo "flip-versioning: enabling object versioning on $bucket"
gcloud storage buckets update "$bucket" --versioning
echo "flip-versioning: done, verifying"
gcloud storage buckets describe "$bucket" --format="value(versioning.enabled)"
