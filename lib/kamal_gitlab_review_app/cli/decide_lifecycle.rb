# frozen_string_literal: true

require 'kamal_gitlab_review_app'

iid = ARGV.fetch(0) { ENV.fetch('CI_MERGE_REQUEST_IID') }
container_names = if $stdin.tty?
                    `docker ps --format '{{.Names}}'`.split("\n")
                  else
                    $stdin.read.split("\n")
                  end

action = KamalGitlabReviewApp::LifecycleDecider.call(iid:, container_names:)
puts action
