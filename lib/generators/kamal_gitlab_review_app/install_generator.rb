# frozen_string_literal: true

require 'rails/generators'
require 'kamal_gitlab_review_app'

class KamalGitlabReviewApp::InstallGenerator < Rails::Generators::Base
  source_root File.expand_path('templates', __dir__)

  desc 'Install kamal-gitlab-review-app: deploy.review.yml and bin/review-apps'

  class_option :force, type: :boolean, default: false,
               desc: 'Overwrite existing generated files'

  def copy_deploy_review
    template 'deploy.review.yml', 'config/deploy.review.yml', force: options[:force]
  end

  def copy_bin_wrapper
    template 'bin/review-apps', 'bin/review-apps', force: options[:force]
    chmod 'bin/review-apps', 0o755
  end
end
