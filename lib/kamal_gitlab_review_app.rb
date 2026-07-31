# frozen_string_literal: true

require 'active_support/core_ext/object/blank'

require_relative 'kamal_gitlab_review_app/version'
require_relative 'kamal_gitlab_review_app/configuration'
require_relative 'kamal_gitlab_review_app/naming'
require_relative 'kamal_gitlab_review_app/runtime_env'
require_relative 'kamal_gitlab_review_app/lifecycle_decider'
require_relative 'kamal_gitlab_review_app/cloudflare_dns'

module KamalGitlabReviewApp
  class << self
    def root
      File.expand_path('..', __dir__)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
