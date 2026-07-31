# frozen_string_literal: true

require 'fileutils'
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
        runtime_env = write_runtime_env(iid:)
        write_secrets_review(runtime_env)
        export_runtime_env(runtime_env)

        upsert_dns(iid:)

        action = decide_action(iid:)
        run!('bundle', 'exec', 'kamal', 'registry', 'setup', '-d', 'review')
        run!('bundle', 'exec', 'kamal', action.to_s, '-d', 'review')
        nil
      end

      def write_runtime_env(iid:)
        runtime_env = KamalGitlabReviewApp::RuntimeEnv.to_h(iid:)
        FileUtils.mkdir_p('.kamal')
        File.write('.kamal/review.env', runtime_env.map { |key, value| "#{key}=#{value}" }.join("\n") << "\n")
        runtime_env
      end

      def write_secrets_review(runtime_env)
        secrets_file = ENV.fetch('SECRETS_REVIEW_FILE')
        destination = '.kamal/secrets.review'
        FileUtils.cp(secrets_file, destination)
        File.open(destination, 'a') do |file|
          runtime_env.each { |key, value| file.puts "#{key}=#{value}" }
        end
        File.chmod(0o600, destination)
      end

      def export_runtime_env(runtime_env)
        runtime_env.each { |key, value| ENV[key] = value }
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
