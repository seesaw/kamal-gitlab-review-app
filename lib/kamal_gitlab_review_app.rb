# frozen_string_literal: true

require_relative 'kamal_gitlab_review_app/version'
require_relative 'kamal_gitlab_review_app/env'
require_relative 'kamal_gitlab_review_app/naming'
require_relative 'kamal_gitlab_review_app/runtime_env'
require_relative 'kamal_gitlab_review_app/lifecycle_decider'
require_relative 'kamal_gitlab_review_app/dns/provider'
require_relative 'kamal_gitlab_review_app/dns/registry'
require_relative 'kamal_gitlab_review_app/dns/cloudflare'

module KamalGitlabReviewApp
  Dns::Registry.register(:cloudflare, Dns::Cloudflare)

  class << self
    def root
      File.expand_path('..', __dir__)
    end
  end
end
