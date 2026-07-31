# frozen_string_literal: true

RSpec.describe KamalGitlabReviewApp::Remote::DockerCleanup do
  include_context 'with review app env'

  describe '.call' do
    it 'invokes the runner with the expected ssh argv and a stdin script' do
      recorded_args = nil
      recorded_script = nil
      runner = lambda do |*args, **kwargs|
        recorded_args = args
        recorded_script = File.read(kwargs.fetch(:in))
        true
      end

      described_class.call(iid: '42', ssh_user: 'deploy', target_ip: '203.0.113.10', runner:)

      expect(recorded_args).to eq(['ssh', 'deploy@203.0.113.10', 'bash', '-s', '--', 'app_mr_42'])
      expect(recorded_script).to include('SERVICE_PREFIX="$1"')
    end

    it 'derives the service prefix from Env.service_prefix and the given iid' do
      ENV['REVIEW_SERVICE_PREFIX'] = 'myapp_mr'
      recorded_args = nil
      runner = lambda { |*args, **| recorded_args = args; true }

      described_class.call(iid: '7', ssh_user: 'deploy', target_ip: '10.0.0.1', runner:)

      expect(recorded_args.last).to eq('myapp_mr_7')
    end

    it 'defaults ssh_user and target_ip from ENV' do
      ENV['REVIEW_SSH_USER'] = 'ci-deploy'
      ENV['REVIEW_TARGET_IP'] = '198.51.100.5'
      recorded_args = nil
      runner = lambda { |*args, **| recorded_args = args; true }

      described_class.call(iid: '9', runner:)

      expect(recorded_args[0..1]).to eq(['ssh', 'ci-deploy@198.51.100.5'])
    ensure
      ENV.delete('REVIEW_SSH_USER')
      ENV.delete('REVIEW_TARGET_IP')
    end

    it 'raises when the runner returns falsy' do
      runner = lambda { |*, **| false }

      expect {
        described_class.call(iid: '42', ssh_user: 'deploy', target_ip: '203.0.113.10', runner:)
      }.to raise_error(/remote docker cleanup failed for app_mr_42/)
    end
  end

  describe 'REMOTE_SCRIPT' do
    it 'guards container, volume, and image removal by the service prefix' do
      script = described_class::REMOTE_SCRIPT

      expect(script).to include('"${SERVICE_PREFIX}"*')
      expect(script).to include('docker rm -f')
      expect(script).to include('docker volume rm')
      expect(script).to include('docker image rm')
    end
  end
end
