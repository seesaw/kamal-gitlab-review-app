#!/usr/bin/env bash
set -euo pipefail

# Thin bash-compatibility shim for CI / host-app wrappers (bin/review-apps).
# Shell and CI invoke the gem exe; the exe does not call this file.
# Command dispatch, DNS, lifecycle decisions, and remote cleanup live in Ruby
# (KamalGitlabReviewApp::CLI).
exec bundle exec kamal-gitlab-review-app "$@"
