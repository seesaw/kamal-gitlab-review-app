#!/usr/bin/env bash
set -euo pipefail

# Standalone remote cleanup — does not source common.sh (runs over SSH, no gem paths needed).
# Invoked from stop_review.sh after Kamal teardown; safe to run alone for orphaned resources.

IID="${1:-${CI_MERGE_REQUEST_IID:-}}"
if [ -z "${IID}" ]; then
  echo "missing MR IID for docker cleanup"
  exit 1
fi

REVIEW_SSH_USER="${REVIEW_SSH_USER:-deploy}"
REVIEW_TARGET_IP="${REVIEW_TARGET_IP:?missing REVIEW_TARGET_IP}"
# Must match KamalGitlabReviewApp::Naming service prefix for this MR.
SERVICE_PREFIX="${REVIEW_SERVICE_PREFIX:-app_mr}_${IID}"

# Heredoc runs on the review host; quoted delimiter prevents local variable expansion.
ssh "${REVIEW_SSH_USER}@${REVIEW_TARGET_IP}" bash -s -- "${SERVICE_PREFIX}" <<'REMOTE'
set -euo pipefail
SERVICE_PREFIX="$1"

# Prefix match: only touch resources belonging to this MR review app.
docker ps -a --format '{{.Names}}' | while read -r container; do
  case "${container}" in
    "${SERVICE_PREFIX}"* ) docker rm -f "${container}" || true ;;
  esac
done

docker volume ls --format '{{.Name}}' | while read -r volume; do
  case "${volume}" in
    "${SERVICE_PREFIX}"* ) docker volume rm "${volume}" || true ;;
  esac
done

docker image ls --format '{{.Repository}}:{{.Tag}}' | while read -r image; do
  case "${image}" in
    *"${SERVICE_PREFIX}"* ) docker image rm "${image}" || true ;;
  esac
done

# Kamal accessory host dirs (e.g. circle_backoffice_mr_679-db).
# `kamal accessory remove` runs plain `rm -rf`, which fails on Postgres data/
# owned by the container UID (Permission denied). Upstream: basecamp/kamal#516.
# Wipe contents as root via Docker, then remove the deploy-owned parent dir.
for dir in "${SERVICE_PREFIX}"-*; do
  [ -d "${dir}" ] || continue
  docker run --rm -v "${PWD}/${dir}:/wipe" alpine:3 \
    sh -c 'find /wipe -mindepth 1 -delete' || true
  rm -rf "${dir}" || true
done
REMOTE
