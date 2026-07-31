#!/usr/bin/env bash
# Shared helpers for review-app CI scripts. Sourced, not executed.
#
# Path resolution uses BASH_SOURCE[0] (this file), not the caller's $0, so
# GEM_ROOT is correct regardless of which ci/*.sh sources us. Three levels up
# from ci/ → kamal_gitlab_review_app/ → lib/ → gem root (same as KamalGitlabReviewApp.root).

GEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CI_DIR="${GEM_ROOT}/lib/kamal_gitlab_review_app/ci"
CLI_DIR="${GEM_ROOT}/lib/kamal_gitlab_review_app/cli"

cli_path() {
  echo "${CLI_DIR}/$1"
}

# deploy.review.yml ERB reads KAMAL_SERVICE / GENERAL_HOST from process ENV,
# not from .kamal/secrets.review (that file only feeds container secrets).
export_review_runtime_env() {
  local env_file="${1:?missing review.env path}"
  # set -a exports every variable sourced from review.env into the current shell
  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
}
