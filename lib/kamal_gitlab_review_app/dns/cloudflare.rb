# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module KamalGitlabReviewApp
  module Dns
    class Cloudflare
      include Provider

      API_BASE_URL = 'https://api.cloudflare.com/client/v4'

      def self.build_a_payload(name:, ip:, ttl:)
        { type: 'A', name:, content: ip, ttl:, proxied: false }
      end

      def upsert_a_record!(name:, ip:, ttl: 120)
        payload = self.class.build_a_payload(name:, ip:, ttl:)
        record = find_record_by_name(name:)

        if record
          request_json!(:put, "/zones/#{zone_id}/dns_records/#{record.fetch('id')}", payload)
        else
          request_json!(:post, "/zones/#{zone_id}/dns_records", payload)
        end
      end

      def delete_record!(name:)
        record = find_record_by_name(name:)
        return nil unless record

        request_json!(:delete, "/zones/#{zone_id}/dns_records/#{record.fetch('id')}")
      end

      private

      def find_record_by_name(name:)
        encoded_name = URI.encode_www_form_component(name)
        response = request_json!(:get, "/zones/#{zone_id}/dns_records?type=A&name=#{encoded_name}")
        response.fetch('result', []).first
      end

      def request_json!(method, path, payload = nil)
        uri = URI("#{API_BASE_URL}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = net_http_request(method, uri, payload)
        response = http.request(request)
        parsed = JSON.parse(response.body)

        raise Dns::Error, "Cloudflare request failed: #{parsed}" unless parsed['success']

        parsed
      end

      def net_http_request(method, uri, payload) # rubocop:disable Metrics/MethodLength
        klass = case method
                when :get then Net::HTTP::Get
                when :post then Net::HTTP::Post
                when :put then Net::HTTP::Put
                when :delete then Net::HTTP::Delete
                else
                  raise ArgumentError, "Unsupported HTTP method: #{method.inspect}"
                end

        request = klass.new(uri)
        request['Authorization'] = "Bearer #{api_token}"
        request['Content-Type'] = 'application/json'
        request.body = JSON.dump(payload) if payload
        request
      end

      def api_token
        ENV.fetch('CLOUDFLARE_API_TOKEN')
      end

      def zone_id
        ENV.fetch('CLOUDFLARE_ZONE_ID')
      end
    end
  end
end
