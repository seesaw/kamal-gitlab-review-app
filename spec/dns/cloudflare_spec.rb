# frozen_string_literal: true

RSpec.describe KamalGitlabReviewApp::Dns::Cloudflare do
  subject(:provider) { described_class.new }

  let(:name) { 'mr-22.review.example.com' }
  let(:ip) { '176.9.147.43' }

  around do |example|
    previous_token = ENV['CLOUDFLARE_API_TOKEN']
    previous_zone = ENV['CLOUDFLARE_ZONE_ID']
    ENV['CLOUDFLARE_API_TOKEN'] = 'test-token'
    ENV['CLOUDFLARE_ZONE_ID'] = 'zone123'

    example.run
  ensure
    previous_token.nil? ? ENV.delete('CLOUDFLARE_API_TOKEN') : ENV['CLOUDFLARE_API_TOKEN'] = previous_token
    previous_zone.nil? ? ENV.delete('CLOUDFLARE_ZONE_ID') : ENV['CLOUDFLARE_ZONE_ID'] = previous_zone
  end

  describe '.build_a_payload' do
    it 'builds upsert payload with proxied false' do
      payload = described_class.build_a_payload(name:, ip:, ttl: 120)

      expect(payload).to include(
        type: 'A',
        name:,
        content: ip,
        ttl: 120,
        proxied: false
      )
    end
  end

  describe '#upsert_a_record!' do
    it 'creates a new record when none exists' do
      stub_request(:get, %r{\Ahttps://api\.cloudflare\.com/client/v4/zones/zone123/dns_records})
        .to_return(status: 200, body: { success: true, result: [] }.to_json)
      create_stub = stub_request(:post, 'https://api.cloudflare.com/client/v4/zones/zone123/dns_records')
                     .with(body: hash_including('name' => name, 'content' => ip))
                     .to_return(status: 200, body: { success: true, result: { id: 'rec1' } }.to_json)

      provider.upsert_a_record!(name:, ip:, ttl: 120)

      expect(create_stub).to have_been_requested
    end

    it 'updates the existing record when one is found' do
      stub_request(:get, %r{\Ahttps://api\.cloudflare\.com/client/v4/zones/zone123/dns_records})
        .to_return(status: 200, body: { success: true, result: [{ id: 'rec1' }] }.to_json)
      update_stub = stub_request(:put, 'https://api.cloudflare.com/client/v4/zones/zone123/dns_records/rec1')
                    .with(body: hash_including('name' => name, 'content' => ip))
                    .to_return(status: 200, body: { success: true, result: { id: 'rec1' } }.to_json)

      provider.upsert_a_record!(name:, ip:, ttl: 120)

      expect(update_stub).to have_been_requested
    end

    it 'raises Dns::Error when the Cloudflare API reports failure' do
      stub_request(:get, %r{\Ahttps://api\.cloudflare\.com/client/v4/zones/zone123/dns_records})
        .to_return(status: 200, body: { success: false, errors: ['boom'] }.to_json)

      expect { provider.upsert_a_record!(name:, ip:, ttl: 120) }
        .to raise_error(KamalGitlabReviewApp::Dns::Error, /Cloudflare request failed/)
    end

    it 'raises Dns::Error when the response body is not JSON' do
      stub_request(:get, %r{\Ahttps://api\.cloudflare\.com/client/v4/zones/zone123/dns_records})
        .to_return(status: 502, body: '<html>Bad Gateway</html>')

      expect { provider.upsert_a_record!(name:, ip:, ttl: 120) }
        .to raise_error(KamalGitlabReviewApp::Dns::Error, /Cloudflare request failed/)
    end

    it 'raises Dns::Error when HTTP status is not success even if body looks ok' do
      stub_request(:get, %r{\Ahttps://api\.cloudflare\.com/client/v4/zones/zone123/dns_records})
        .to_return(status: 500, body: { success: true, result: [] }.to_json)

      expect { provider.upsert_a_record!(name:, ip:, ttl: 120) }
        .to raise_error(KamalGitlabReviewApp::Dns::Error, /HTTP 500/)
    end

    it 'configures open and read timeouts on the HTTP client' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(
        instance_double(Net::HTTPResponse, code: '200', body: { success: true, result: [] }.to_json)
      )

      provider.upsert_a_record!(name:, ip:, ttl: 120)

      expect(http).to have_received(:open_timeout=).with(described_class::OPEN_TIMEOUT).at_least(:once)
      expect(http).to have_received(:read_timeout=).with(described_class::READ_TIMEOUT).at_least(:once)
    end

    it 'wraps network timeouts as Dns::Error' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_raise(Net::OpenTimeout)

      expect { provider.upsert_a_record!(name:, ip:, ttl: 120) }
        .to raise_error(KamalGitlabReviewApp::Dns::Error, /timed out|timeout/i)
    end
  end

  describe '#delete_record!' do
    it 'deletes the record when one is found' do
      stub_request(:get, %r{\Ahttps://api\.cloudflare\.com/client/v4/zones/zone123/dns_records})
        .to_return(status: 200, body: { success: true, result: [{ id: 'rec1' }] }.to_json)
      delete_stub = stub_request(:delete, 'https://api.cloudflare.com/client/v4/zones/zone123/dns_records/rec1')
                    .to_return(status: 200, body: { success: true, result: {} }.to_json)

      provider.delete_record!(name:)

      expect(delete_stub).to have_been_requested
    end

    it 'returns nil when no record is found' do
      stub_request(:get, %r{\Ahttps://api\.cloudflare\.com/client/v4/zones/zone123/dns_records})
        .to_return(status: 200, body: { success: true, result: [] }.to_json)

      expect(provider.delete_record!(name:)).to be_nil
    end
  end
end
