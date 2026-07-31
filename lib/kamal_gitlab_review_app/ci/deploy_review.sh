#!/usr/bin/env bash
set -euo pipefail

# Sibling source: dirname of this script is ci/, so common.sh is always next to us.
# No Ruby/Bundler needed to bootstrap paths (see common.sh).
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Kamal reads config from the app repo root (.kamal/, config/deploy.review.yml).
PROJECT_ROOT="${KAMAL_GITLAB_REVIEW_APP_PROJECT_ROOT:-$(pwd)}"
cd "${PROJECT_ROOT}"

IID="${CI_MERGE_REQUEST_IID:?missing CI_MERGE_REQUEST_IID}"

mkdir -p .kamal

# Per-MR runtime vars (service name, host, etc.) — generated, not checked in.
bundle exec ruby "$(cli_path write_runtime_env.rb)" "${IID}" > .kamal/review.env
# Static review secrets from CI variable; append runtime vars for Kamal container secrets.
cp "${SECRETS_REVIEW_FILE:?missing SECRETS_REVIEW_FILE}" .kamal/secrets.review
cat .kamal/review.env >> .kamal/secrets.review
# Kamal ERB and CLI need KAMAL_SERVICE / GENERAL_HOST in the shell ENV too.
export_review_runtime_env .kamal/review.env

bundle exec ruby "$(cli_path dns_upsert.rb)" "${IID}"

REVIEW_SSH_USER="${REVIEW_SSH_USER:-deploy}"
REVIEW_TARGET_IP="${REVIEW_TARGET_IP:?missing REVIEW_TARGET_IP}"
# List remote containers to decide first-time setup vs redeploy.
REMOTE_CONTAINERS="$(ssh "${REVIEW_SSH_USER}@${REVIEW_TARGET_IP}" "docker ps --format '{{.Names}}'" || true)"

ACTION="$(printf '%s\n' "${REMOTE_CONTAINERS}" | bundle exec ruby "$(cli_path decide_lifecycle.rb)" "${IID}")"
bundle exec kamal registry setup -d review # necessary to avoid registry credentials errors

if [ "${ACTION}" = "setup" ]; then
  bundle exec kamal setup -d review
else
  bundle exec kamal deploy -d review
fi
