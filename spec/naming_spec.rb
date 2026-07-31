# frozen_string_literal: true

RSpec.describe KamalGitlabReviewApp::Naming do
  include_context 'with review app env'

  describe '.for_mr' do
    it 'builds deterministic names from MR IID' do
      result = described_class.for_mr(iid: '123')

      aggregate_failures do
        expect(result[:environment_name]).to eq('review/mr-123')
        expect(result[:host]).to eq('mr-123.review.circle.seesaw.it')
        expect(result[:service]).to eq('circle_backoffice_mr_123')
        expect(result[:db_host]).to eq('circle_backoffice_mr_123-db')
      end
    end

    it 'requires REVIEW_DOMAIN' do
      ENV.delete('REVIEW_DOMAIN')
      KamalGitlabReviewApp.reset_configuration!

      expect { described_class.for_mr(iid: '1') }.to raise_error(KeyError, /REVIEW_DOMAIN/)
    end
  end
end
