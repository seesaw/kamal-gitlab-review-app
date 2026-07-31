# frozen_string_literal: true

RSpec.shared_context 'with review app env' do
  around do |example|
    keys = %w[REVIEW_DOMAIN REVIEW_SERVICE_PREFIX]
    previous = keys.to_h { |key| [key, ENV[key]] }

    ENV['REVIEW_DOMAIN'] = 'review.circle.seesaw.it'
    ENV['REVIEW_SERVICE_PREFIX'] = 'circle_backoffice_mr'
    KamalGitlabReviewApp.reset_configuration!

    example.run
  ensure
    keys.each do |key|
      previous[key].nil? ? ENV.delete(key) : ENV[key] = previous[key]
    end
    KamalGitlabReviewApp.reset_configuration!
  end
end
