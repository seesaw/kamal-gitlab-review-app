# frozen_string_literal: true

RSpec.shared_context 'with review app env' do
  around do |example|
    keys = %w[
      REVIEW_DOMAIN REVIEW_SERVICE_PREFIX REVIEW_ENVIRONMENT_PREFIX
      REVIEW_HOST_LABEL_PREFIX REVIEW_DNS_PROVIDER REVIEW_ACCESSORIES
      REVIEW_DB_ACCESSORY
    ]
    previous = keys.to_h { |key| [key, ENV[key]] }

    ENV['REVIEW_DOMAIN'] = 'review.example.com'
    ENV['REVIEW_SERVICE_PREFIX'] = 'app_mr'
    ENV.delete('REVIEW_ENVIRONMENT_PREFIX')
    ENV.delete('REVIEW_HOST_LABEL_PREFIX')
    ENV.delete('REVIEW_DNS_PROVIDER')
    ENV.delete('REVIEW_ACCESSORIES')
    ENV.delete('REVIEW_DB_ACCESSORY')

    example.run
  ensure
    keys.each do |key|
      previous[key].nil? ? ENV.delete(key) : ENV[key] = previous[key]
    end
  end
end
