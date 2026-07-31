# frozen_string_literal: true

require 'kamal_gitlab_review_app'

iid = ARGV.fetch(0) { ENV.fetch('CI_MERGE_REQUEST_IID') }
host = KamalGitlabReviewApp::Naming.for_mr(iid:).fetch(:host)

provider = KamalGitlabReviewApp::Dns::Registry.resolve
provider.delete_record!(name: host)
puts "dns_delete:#{host}"
