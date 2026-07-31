#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "${KAMAL_GITLAB_REVIEW_APP_PROJECT_ROOT:-$(pwd)}"
exec bundle exec kamal-gitlab-review-app stop
