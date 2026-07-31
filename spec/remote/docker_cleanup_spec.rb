# frozen_string_literal: true

require 'open3'
require 'shellwords'

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

      expect(script).to include('matches_service_resource')
      expect(script).to include('matches_service_image')
      expect(script).not_to include('"${SERVICE_PREFIX}"*')
      expect(script).to include('docker rm -f')
      expect(script).to include('docker volume rm')
      expect(script).to include('docker image rm')
    end

    it 'matches only the exact MR service prefix (not app_mr_10 for app_mr_1)' do
      matched = bash_match_resources(
        'app_mr_1',
        %w[app_mr_1 app_mr_1-web app_mr_1_worker app_mr_10-web app_mr_11-db app_mr_1x-web other_app_mr_1-web]
      )

      expect(matched).to eq(%w[app_mr_1 app_mr_1-web app_mr_1_worker])
    end

    it 'matches images for the exact service prefix only' do
      matched = bash_match_images(
        'app_mr_1',
        %w[
          app_mr_1:abc
          registry.example/app_mr_1:abc
          app_mr_10:abc
          registry.example/app_mr_10:abc
          other/app_mr_1@sha256:deadbeef
        ]
      )

      expect(matched).to eq(%w[app_mr_1:abc registry.example/app_mr_1:abc other/app_mr_1@sha256:deadbeef])
    end
  end

  def bash_match_resources(prefix, names)
    bash_filter(prefix, names, 'matches_service_resource')
  end

  def bash_match_images(prefix, names)
    bash_filter(prefix, names, 'matches_service_image')
  end

  def bash_filter(prefix, names, matcher)
    script = <<~BASH
      set -euo pipefail
      SERVICE_PREFIX=#{Shellwords.escape(prefix)}
      #{described_class::REMOTE_SCRIPT[/matches_service_resource\(\) \{.*?\n\}/m]}
      #{described_class::REMOTE_SCRIPT[/matches_service_image\(\) \{.*?\n\}/m]}
      for name in #{Shellwords.join(names)}; do
        if #{matcher} "$name"; then
          printf '%s\n' "$name"
        fi
      done
    BASH

    stdout, status = Open3.capture2('bash', '-c', script)
    raise "bash matcher failed:\n#{stdout}" unless status.success?

    stdout.split("\n")
  end
end
