# frozen_string_literal: true

module KamalGitlabReviewApp
  module Env
    module_function

    def review_domain
      value = ENV['REVIEW_DOMAIN'].to_s.strip
      raise KeyError, 'key not found: "REVIEW_DOMAIN"' if value.empty?

      value
    end

    def service_prefix
      ENV.fetch('REVIEW_SERVICE_PREFIX', 'app_mr')
    end

    def environment_prefix
      ENV.fetch('REVIEW_ENVIRONMENT_PREFIX', 'review/mr')
    end

    def host_label_prefix
      ENV.fetch('REVIEW_HOST_LABEL_PREFIX', 'mr')
    end

    def dns_provider_name
      ENV.fetch('REVIEW_DNS_PROVIDER', 'cloudflare').to_s.strip.downcase
    end

    def accessories
      raw = ENV.fetch('REVIEW_ACCESSORIES', 'db').to_s.strip
      return [] if raw.empty? || raw.downcase == 'none'

      raw.split(',').map(&:strip).reject(&:empty?)
    end

    # Accessory name used for DB_HOST (`#{service}-#{accessory}`). Defaults to the first
    # entry in REVIEW_ACCESSORIES; override with REVIEW_DB_ACCESSORY when the DB is not first.
    def db_accessory
      explicit = ENV['REVIEW_DB_ACCESSORY'].to_s.strip
      return explicit unless explicit.empty?

      accessories.first
    end

    def default_runtime_env(names)
      env = {
        'GENERAL_HOST' => names.fetch(:host),
        'KAMAL_SERVICE' => names.fetch(:service)
      }
      env['DB_HOST'] = names[:db_host] if names[:db_host]
      env
    end
  end
end
