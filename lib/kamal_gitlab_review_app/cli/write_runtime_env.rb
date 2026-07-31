# frozen_string_literal: true

require 'kamal_gitlab_review_app'

iid = ARGV.fetch(0) { ENV.fetch('CI_MERGE_REQUEST_IID') }

KamalGitlabReviewApp::RuntimeEnv.to_h(iid:).sort.each do |key, value|
  puts "#{key}=#{value}"
end
