# frozen_string_literal: true

RSpec.describe KamalGitlabReviewApp::RuntimeEnv do
  include_context 'with review app env'

  describe '.to_h' do
    it 'exposes only per-MR dynamic variables' do
      env = described_class.to_h(iid: '91')

      expect(env).to eq(
        'GENERAL_HOST' => 'mr-91.review.circle.seesaw.it',
        'DB_HOST' => 'circle_backoffice_mr_91-db',
        'KAMAL_SERVICE' => 'circle_backoffice_mr_91'
      )
    end
  end
end
