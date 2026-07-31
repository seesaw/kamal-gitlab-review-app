# frozen_string_literal: true

RSpec.describe KamalGitlabReviewApp::Dns::Registry do
  before { described_class.reset! }

  after do
    described_class.reset!
    described_class.register(:cloudflare, KamalGitlabReviewApp::Dns::Cloudflare)
  end

  it 'resolves the default cloudflare provider' do
    described_class.register(:cloudflare, KamalGitlabReviewApp::Dns::Cloudflare)
    expect(described_class.resolve).to be_a(KamalGitlabReviewApp::Dns::Cloudflare)
  end

  it 'resolves a custom registered provider from REVIEW_DNS_PROVIDER' do
    fake = Class.new do
      def upsert_a_record!(**); end
      def delete_record!(**); end
    end
    described_class.register(:fake, fake)
    ENV['REVIEW_DNS_PROVIDER'] = 'fake'
    expect(described_class.resolve).to be_a(fake)
  ensure
    ENV.delete('REVIEW_DNS_PROVIDER')
  end

  it 'raises when provider is unknown' do
    ENV['REVIEW_DNS_PROVIDER'] = 'missing'
    expect { described_class.resolve }.to raise_error(KamalGitlabReviewApp::Dns::Error, /missing/)
  ensure
    ENV.delete('REVIEW_DNS_PROVIDER')
  end
end
