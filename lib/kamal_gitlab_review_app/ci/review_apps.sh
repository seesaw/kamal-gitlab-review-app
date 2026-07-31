#!/usr/bin/env bash
set -euo pipefail

# Entry point invoked by exe/kamal-gitlab-review-app (bin/review-apps in the host app).
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: review-apps <command> [args...]

Commands:
  deploy         Deploy or setup the MR review app
  stop           Tear down the MR review app
  runtime-env    Print runtime env for an MR IID
  decide         Decide setup vs deploy from remote container list
  dns-upsert     Upsert Cloudflare DNS for an MR IID
  dns-delete     Delete Cloudflare DNS for an MR IID
EOF
  exit "${1:-1}"
}

if [ $# -lt 1 ]; then
  usage
fi

cmd="$1"
shift

case "${cmd}" in
  deploy)
    exec bash "${CI_DIR}/deploy_review.sh" "$@"
    ;;
  stop)
    exec bash "${CI_DIR}/stop_review.sh" "$@"
    ;;
  # Standalone CLI helpers for debugging / ad-hoc CI steps (no Kamal orchestration).
  runtime-env)
    exec bundle exec ruby "${CLI_DIR}/write_runtime_env.rb" "$@"
    ;;
  decide)
    exec bundle exec ruby "${CLI_DIR}/decide_lifecycle.rb" "$@"
    ;;
  dns-upsert)
    exec bundle exec ruby "${CLI_DIR}/dns_upsert.rb" "$@"
    ;;
  dns-delete)
    exec bundle exec ruby "${CLI_DIR}/dns_delete.rb" "$@"
    ;;
  -h|--help|help)
    usage 0
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    usage 1
    ;;
esac
