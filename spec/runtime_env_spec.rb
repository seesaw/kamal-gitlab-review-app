# frozen_string_literal: true

RSpec.describe KamalGitlabReviewApp::RuntimeEnv do
  include_context 'with review app env'

  describe '.to_h' do
    it 'exposes only per-MR dynamic variables' do
      env = described_class.to_h(iid: '91')

      expect(env).to eq(
        'GENERAL_HOST' => 'mr-91.review.example.com',
        'DB_HOST' => 'app_mr_91-db',
        'KAMAL_SERVICE' => 'app_mr_91'
      )
    end

    it 'omits DB_HOST when there are no accessories' do
      ENV['REVIEW_ACCESSORIES'] = 'none'

      expect(described_class.to_h(iid: '91')).to eq(
        'GENERAL_HOST' => 'mr-91.review.example.com',
        'KAMAL_SERVICE' => 'app_mr_91'
      )
    end
  end

  describe '.default_hash' do
    it 'returns GENERAL_HOST/KAMAL_SERVICE/DB_HOST for the MR names' do
      names = KamalGitlabReviewApp::Naming.for_mr(iid: '91')

      expect(described_class.default_hash(names)).to eq(
        'GENERAL_HOST' => 'mr-91.review.example.com',
        'KAMAL_SERVICE' => 'app_mr_91',
        'DB_HOST' => 'app_mr_91-db'
      )
    end
  end
end
