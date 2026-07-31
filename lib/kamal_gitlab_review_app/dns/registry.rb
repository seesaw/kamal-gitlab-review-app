# frozen_string_literal: true

module KamalGitlabReviewApp
  module Dns
    module Registry
      class << self
        def register(name, klass)
          providers[name.to_sym] = klass
        end

        def resolve
          key = KamalGitlabReviewApp::Env.dns_provider_name.to_sym
          klass = providers[key]
          unless klass
            raise Error, "Unknown DNS provider #{key.inspect}. Registered: #{providers.keys.sort.join(', ')}"
          end

          klass.new
        end

        def reset!
          @providers = {}
        end

        private

        def providers
          @providers ||= {}
        end
      end
    end
  end
end
