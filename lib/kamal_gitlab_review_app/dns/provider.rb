# frozen_string_literal: true

module KamalGitlabReviewApp
  module Dns
    class Error < StandardError; end

    # Contract for DNS adapters (document in docs/dns-providers.md):
    #   #upsert_a_record!(name:, ip:, ttl:)
    #   #delete_record!(name:)
    module Provider
    end
  end
end
