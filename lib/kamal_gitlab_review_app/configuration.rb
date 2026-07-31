# frozen_string_literal: true

module KamalGitlabReviewApp
  class Configuration
    attr_accessor :review_domain,
                  :service_prefix,
                  :environment_prefix,
                  :host_label_prefix

    def initialize
      @review_domain = ENV['REVIEW_DOMAIN']
      @service_prefix = ENV.fetch('REVIEW_SERVICE_PREFIX', 'app_mr')
      @environment_prefix = ENV.fetch('REVIEW_ENVIRONMENT_PREFIX', 'review/mr')
      @host_label_prefix = ENV.fetch('REVIEW_HOST_LABEL_PREFIX', 'mr')
    end

    def review_domain!
      review_domain.presence || ENV.fetch('REVIEW_DOMAIN')
    end

    # Only values that must differ per MR. DB_* names stay in SECRETS_REVIEW_FILE:
    # each review app has its own Postgres accessory container.
    def default_runtime_env(names)
      {
        'GENERAL_HOST' => names.fetch(:host),
        'KAMAL_SERVICE' => names.fetch(:service),
        'DB_HOST' => names.fetch(:db_host)
      }
    end
  end
end
