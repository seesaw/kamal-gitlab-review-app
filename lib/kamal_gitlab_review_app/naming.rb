# frozen_string_literal: true

module KamalGitlabReviewApp
  class Naming
    class << self
      def for_mr(iid:)
        iid_str = normalize_iid(iid)
        config = KamalGitlabReviewApp.configuration
        service = "#{config.service_prefix}_#{iid_str}"

        {
          environment_name: "#{config.environment_prefix}-#{iid_str}",
          host: "#{config.host_label_prefix}-#{iid_str}.#{config.review_domain!}",
          service: service,
          # Kamal accessory container name is "#{service}-#{accessory}" (see Kamal::Configuration::Accessory#service_name).
          db_host: "#{service}-db"
        }
      end

      private

      def normalize_iid(iid)
        value = iid.to_s.strip
        raise ArgumentError, 'MR IID is required' if value.empty?

        value
      end
    end
  end
end
