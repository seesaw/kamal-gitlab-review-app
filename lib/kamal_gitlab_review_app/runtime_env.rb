# frozen_string_literal: true

module KamalGitlabReviewApp
  class RuntimeEnv
    class << self
      def to_h(iid:, overrides: {})
        names = KamalGitlabReviewApp::Naming.for_mr(iid:)
        defaults = KamalGitlabReviewApp.configuration.default_runtime_env(names)

        defaults.merge(stringify_keys(overrides))
      end

      private

      def stringify_keys(hash)
        hash.to_h.transform_keys(&:to_s)
      end
    end
  end
end
