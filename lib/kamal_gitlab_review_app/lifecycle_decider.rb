# frozen_string_literal: true

module KamalGitlabReviewApp
  class LifecycleDecider
    class << self
      def call(iid:, container_names:)
        service = KamalGitlabReviewApp::Naming.for_mr(iid:).fetch(:service)
        normalized = Array(container_names).map(&:to_s)

        normalized.any? { |name| service_prefix_match?(name, service) } ? :deploy : :setup
      end

      private

      def service_prefix_match?(container_name, service)
        container_name.match?(/\A#{Regexp.escape(service)}(?:[-_].*|\z)/)
      end
    end
  end
end
