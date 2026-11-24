# frozen_string_literal: true

require_relative '../runtime_files'
require 'open3'

module KamalGitlabReviewApp
  module CLI
    # Deploys (or first-time sets up) the review app for the current MR. Fails loud: any
    # step failure raises and propagates to the caller (no swallowed errors, no exit-0
    # masking of a broken deploy).
    class Deploy
      class Error < StandardError; end

      DEFAULT_CONTAINER_LISTER = lambda do
        ssh_user = ENV.fetch('REVIEW_SSH_USER', 'deploy')
        target_ip = ENV.fetch('REVIEW_TARGET_IP')
        stdout, status = Open3.capture2('ssh', "#{ssh_user}@#{target_ip}", "docker ps --format '{{.Names}}'")
        status.success? ? stdout : ''
      rescue StandardError
        ''
      end

      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(runner: method(:system), container_lister: DEFAULT_CONTAINER_LISTER)
        @runner = runner
        @container_lister = container_lister
      end

      def call
        project_root = ENV.fetch('KAMAL_GITLAB_REVIEW_APP_PROJECT_ROOT', Dir.pwd)
        iid = ENV.fetch('CI_MERGE_REQUEST_IID')

        Dir.chdir(project_root) { deploy(iid:) }
      end

      private

      def deploy(iid:)
        RuntimeFiles.prepare(iid:)

        upsert_dns(iid:)

        action = decide_action(iid:)
        run!('bundle', 'exec', 'kamal', 'registry', 'setup', '-d', 'review')
        run!('bundle', 'exec', 'kamal', action.to_s, '-d', 'review')
        nil
      end

      def upsert_dns(iid:)
        host = KamalGitlabReviewApp::Naming.for_mr(iid:).fetch(:host)
        ip = ENV.fetch('REVIEW_TARGET_IP')
        ttl = ENV.fetch('REVIEW_DNS_TTL', '120').to_i

        KamalGitlabReviewApp::Dns::Registry.resolve.upsert_a_record!(name: host, ip:, ttl:)
      end

      # Remote container listing is best-effort (empty on failure): a brand-new host has no
      # containers yet, and that must be treated as "first setup", not a hard failure.
      def decide_action(iid:)
        container_names = @container_lister.call.to_s.split("\n")
        KamalGitlabReviewApp::LifecycleDecider.call(iid:, container_names:)
      end

      def run!(*cmd)
        raise Error, "Command failed: #{cmd.join(' ')}" unless @runner.call(*cmd)
      end
    end
  end
end
