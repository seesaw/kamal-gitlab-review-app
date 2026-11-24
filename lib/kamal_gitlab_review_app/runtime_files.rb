# frozen_string_literal: true

require 'fileutils'

module KamalGitlabReviewApp
  class RuntimeFiles
    class << self
      def prepare(iid:)
        runtime = RuntimeEnv.to_h(iid:)
        FileUtils.mkdir_p('.kamal')

        values = serialize(runtime)
        File.write('.kamal/review.env', values)
        write_secrets(values)

        ENV.update(runtime)
        runtime
      end

      private

      def serialize(runtime)
        runtime.map { |key, value| "#{key}=#{value}\n" }.join
      end

      def write_secrets(values)
        secrets = File.read(ENV.fetch('SECRETS_REVIEW_FILE'))
        secrets << "\n" unless secrets.end_with?("\n")
        File.open('.kamal/secrets.review', 'w', 0o600) do |file|
          file.chmod(0o600)
          file.write(secrets + values)
        end
      end
    end
  end
end
