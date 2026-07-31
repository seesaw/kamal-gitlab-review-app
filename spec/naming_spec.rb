# frozen_string_literal: true

RSpec.describe KamalGitlabReviewApp::Naming do
  include_context 'with review app env'

  describe '.for_mr' do
    it 'builds deterministic names from MR IID' do
      result = described_class.for_mr(iid: '123')

      aggregate_failures do
        expect(result[:environment_name]).to eq('review/mr-123')
        expect(result[:host]).to eq('mr-123.review.example.com')
        expect(result[:service]).to eq('app_mr_123')
        expect(result[:db_host]).to eq('app_mr_123-db')
      end
    end

    it 'requires REVIEW_DOMAIN' do
      ENV.delete('REVIEW_DOMAIN')

      expect { described_class.for_mr(iid: '1') }.to raise_error(KeyError, /REVIEW_DOMAIN/)
    end

    it 'derives db_host from the first REVIEW_ACCESSORIES entry' do
      ENV['REVIEW_ACCESSORIES'] = 'postgres,redis'

      expect(described_class.for_mr(iid: '5')[:db_host]).to eq('app_mr_5-postgres')
    end

    it 'prefers REVIEW_DB_ACCESSORY over the accessories list' do
      ENV['REVIEW_ACCESSORIES'] = 'redis,db'
      ENV['REVIEW_DB_ACCESSORY'] = 'db'

      expect(described_class.for_mr(iid: '5')[:db_host]).to eq('app_mr_5-db')
    ensure
      ENV.delete('REVIEW_DB_ACCESSORY')
    end

    it 'omits db_host when there are no accessories' do
      ENV['REVIEW_ACCESSORIES'] = 'none'

      expect(described_class.for_mr(iid: '5')).not_to have_key(:db_host)
    end
  end
end
