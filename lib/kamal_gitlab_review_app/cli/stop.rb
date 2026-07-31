# frozen_string_literal: true

require 'fileutils'

module KamalGitlabReviewApp
  module CLI
    # Tears down the review app for the current MR. Best-effort: every step is isolated so
    # one failure (e.g. Kamal app already gone, DNS record already deleted) never prevents
    # the remaining teardown steps from running. Never raises to the caller.
    #
    # Returns true when at least one top-level step succeeded, false when every step failed
    # (so CI can still surface a fully broken stop while keeping `allow_failure: true`).
    class Stop
      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(runner: method(:system))
        @runner = runner
      end

      def call
        project_root = ENV.fetch('KAMAL_GITLAB_REVIEW_APP_PROJECT_ROOT', Dir.pwd)
        iid = ENV.fetch('CI_MERGE_REQUEST_IID')

        # Kamal teardown needs the project root (config/.kamal/); DNS delete and remote
        # Docker cleanup do not touch the local filesystem at all. Keep them as separate
        # top-level best-effort steps so a bad/unenterable project_root (or any kamal
        # failure) never skips DNS deletion or remote cleanup.
        results = []
        results << best_effort('kamal teardown') { kamal_teardown(project_root:, iid:) }
        results << best_effort('dns delete') { delete_dns(iid:) }
        results << best_effort('remote docker cleanup') {
          KamalGitlabReviewApp::Remote::DockerCleanup.call(iid:, runner: @runner)
        }
        results.any?
      rescue StandardError => e
        warn "kamal-gitlab-review-app stop: #{e.message}"
        false
      end

      private

      def kamal_teardown(project_root:, iid:)
        Dir.chdir(project_root) do
          runtime_env = nil
          best_effort('write runtime env') { runtime_env = write_runtime_env(iid:) }
          export_runtime_env(runtime_env) if runtime_env

          removes = []
          removes << best_effort('kamal app remove') { run!('bundle', 'exec', 'kamal', 'app', 'remove', '-d', 'review') }

          KamalGitlabReviewApp::Env.accessories.each do |name|
            removes << best_effort("kamal accessory remove #{name}") do
              run!('bundle', 'exec', 'kamal', 'accessory', 'remove', name, '-d', 'review', '-y')
            end
          end

          raise 'no kamal remove commands succeeded' unless removes.any?
        end
      end

      def best_effort(step)
        yield
        true
      rescue StandardError => e
        warn "kamal-gitlab-review-app stop: #{step} failed: #{e.message}"
        false
      end

      def write_runtime_env(iid:)
        runtime_env = KamalGitlabReviewApp::RuntimeEnv.to_h(iid:)
        FileUtils.mkdir_p('.kamal')
        File.write('.kamal/review.env', runtime_env.map { |key, value| "#{key}=#{value}" }.join("\n") << "\n")
        runtime_env
      end

      def export_runtime_env(runtime_env)
        runtime_env.each { |key, value| ENV[key] = value }
      end

      def delete_dns(iid:)
        host = KamalGitlabReviewApp::Naming.for_mr(iid:).fetch(:host)
        KamalGitlabReviewApp::Dns::Registry.resolve.delete_record!(name: host)
      end

      def run!(*cmd)
        raise "command failed: #{cmd.join(' ')}" unless @runner.call(*cmd)
      end
    end
  end
end
