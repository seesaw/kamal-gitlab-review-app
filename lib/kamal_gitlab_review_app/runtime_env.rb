# frozen_string_literal: true

module KamalGitlabReviewApp
  class RuntimeEnv
    class << self
      def to_h(iid:, overrides: {})
        names = KamalGitlabReviewApp::Naming.for_mr(iid:)

        default_hash(names).merge(stringify_keys(overrides))
      end

      # Only values that must differ per MR. DB_* names stay in SECRETS_REVIEW_FILE:
      # each review app has its own Postgres accessory container.
      def default_hash(names)
        KamalGitlabReviewApp::Env.default_runtime_env(names)
      end

      private

      def stringify_keys(hash)
        hash.to_h.transform_keys(&:to_s)
      end
    end
  end
end
