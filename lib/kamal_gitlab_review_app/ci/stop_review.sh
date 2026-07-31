#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

PROJECT_ROOT="${KAMAL_GITLAB_REVIEW_APP_PROJECT_ROOT:-$(pwd)}"
cd "${PROJECT_ROOT}"

IID="${CI_MERGE_REQUEST_IID:?missing CI_MERGE_REQUEST_IID}"

mkdir -p .kamal
# Regenerate runtime env so kamal -d review resolves the correct MR service name.
bundle exec ruby "$(cli_path write_runtime_env.rb)" "${IID}" > .kamal/review.env
export_review_runtime_env .kamal/review.env

# Kamal-managed teardown (containers, proxy, accessory hooks).
bundle exec kamal app remove -d review || true
bundle exec kamal accessory remove db -d review -y || true

bundle exec ruby "$(cli_path dns_delete.rb)" "${IID}" || true
# Belt-and-suspenders: remove leftover containers/volumes/images/dirs Kamal may miss.
bash "${CI_DIR}/cleanup_docker.sh" "${IID}" || true
