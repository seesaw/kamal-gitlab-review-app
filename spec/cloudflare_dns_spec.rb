# frozen_string_literal: true

RSpec.describe KamalGitlabReviewApp::CloudflareDns do
  describe '.build_a_payload' do
    it 'builds upsert payload with proxied false' do
      payload = described_class.build_a_payload(name: 'mr-22.review.circle.seesaw.it', ip: '176.9.147.43', ttl: 120)

      expect(payload).to include(
        type: 'A',
        name: 'mr-22.review.circle.seesaw.it',
        content: '176.9.147.43',
        ttl: 120,
        proxied: false
      )
    end
  end
end
