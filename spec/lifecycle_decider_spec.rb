# frozen_string_literal: true

RSpec.describe KamalGitlabReviewApp::LifecycleDecider do
  include_context 'with review app env'

  describe '.call' do
    it 'returns setup when review service is missing' do
      action = described_class.call(iid: '321', container_names: ['app-web-1'])
      expect(action).to eq(:setup)
    end

    it 'returns deploy when review service exists' do
      action = described_class.call(iid: '321', container_names: ['app_mr_321-web-1'])
      expect(action).to eq(:deploy)
    end

    it 'ignores unrelated container names while matching MR service prefix' do
      action = described_class.call(iid: '44', container_names: ['app_mr_441-web-1'])
      expect(action).to eq(:setup)
    end
  end
end
