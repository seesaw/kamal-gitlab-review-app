#!/usr/bin/env bash
# Shared helpers for review-app CI scripts. Sourced, not executed.
#
# Deploy/stop orchestration, DNS, and remote cleanup now live in the Ruby gem
# (KamalGitlabReviewApp::CLI). This file is kept as a hook point for any future
# shared shell-level setup the thin *.sh wrappers might need.
