# frozen_string_literal: true

require_relative 'lib/kamal_gitlab_review_app/version'

Gem::Specification.new do |spec|
  spec.name          = 'kamal-gitlab-review-app'
  spec.version       = KamalGitlabReviewApp::VERSION
  spec.authors       = ['Nicola Pagiaro']
  spec.email         = ['nicola.pagiaro@seesaw.it']
  spec.summary       = 'GitLab MR review apps lifecycle for Kamal deployments'
  spec.description   = 'Deploy and teardown per-merge-request review environments with Kamal, pluggable DNS, and GitLab CI.'
  spec.license       = 'MIT'
  spec.homepage      = 'https://github.com/seesaw/kamal-gitlab-review-app'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/seesaw/kamal-gitlab-review-app'
  spec.metadata['changelog_uri'] = 'https://github.com/seesaw/kamal-gitlab-review-app/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    Dir['lib/**/*', 'exe/*', 'README.md', 'LICENSE', 'CHANGELOG.md', 'docs/**/*'].select { |path| File.file?(path) }
  end
  spec.require_paths = ['lib']
  spec.bindir = 'exe'
  spec.executables = ['kamal-gitlab-review-app']

  spec.required_ruby_version = '>= 3.2'

  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'webmock', '~> 3.23'
end
