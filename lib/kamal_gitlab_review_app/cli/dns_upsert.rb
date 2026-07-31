# frozen_string_literal: true

require 'kamal_gitlab_review_app'

iid = ARGV.fetch(0) { ENV.fetch('CI_MERGE_REQUEST_IID') }
ip = ENV.fetch('REVIEW_TARGET_IP')
ttl = ENV.fetch('REVIEW_DNS_TTL', '120').to_i
host = KamalGitlabReviewApp::Naming.for_mr(iid:).fetch(:host)

KamalGitlabReviewApp::CloudflareDns.upsert_a_record!(name: host, ip:, ttl:)
puts "dns_upsert:#{host}"
