# frozen_string_literal: true

require 'kamal_gitlab_review_app/cli'
require 'tmpdir'

RSpec.describe KamalGitlabReviewApp::CLI do
  include_context 'with review app env'

  describe '.run' do
    it 'prints usage and returns 0 for help' do
      status = nil
      expect { status = described_class.run(['help']) }.to output(/Usage: kamal-gitlab-review-app/).to_stdout
      expect(status).to eq(0)
    end

    it 'prints usage and returns 0 when no command is given' do
      status = nil
      expect { status = described_class.run([]) }.to output(/Usage: kamal-gitlab-review-app/).to_stdout
      expect(status).to eq(0)
    end

    it 'returns non-zero and warns for an unknown command' do
      status = nil
      expect { status = described_class.run(['bogus']) }.to output(/Unknown command: "bogus"/).to_stderr
      expect(status).not_to eq(0)
    end

    it 'returns 1 with a clean message when deploy raises' do
      allow(KamalGitlabReviewApp::CLI::Deploy).to receive(:call)
        .and_raise(KamalGitlabReviewApp::CLI::Deploy::Error, 'Command failed: kamal setup')

      status = nil
      expect { status = described_class.run(['deploy']) }
        .to output(/kamal-gitlab-review-app deploy: Command failed: kamal setup/).to_stderr
      expect(status).to eq(1)
    end

    it 'returns 1 when deploy is missing required ENV' do
      allow(KamalGitlabReviewApp::CLI::Deploy).to receive(:call).and_raise(KeyError, 'key not found: "CI_MERGE_REQUEST_IID"')

      status = nil
      expect { status = described_class.run(['deploy']) }
        .to output(/kamal-gitlab-review-app deploy: key not found: "CI_MERGE_REQUEST_IID"/).to_stderr
      expect(status).to eq(1)
    end

    it 'returns 1 when stop reports that every step failed' do
      allow(KamalGitlabReviewApp::CLI::Stop).to receive(:call).and_return(false)

      expect(described_class.run(['stop'])).to eq(1)
    end

    it 'prints KAMAL_SERVICE for runtime-env with an explicit IID' do
      expect { described_class.run(['runtime-env', '77']) }
        .to output(/KAMAL_SERVICE=app_mr_77/).to_stdout
    end

    it 'reads the MR IID from ENV when omitted' do
      ENV['CI_MERGE_REQUEST_IID'] = '5'
      expect { described_class.run(['runtime-env']) }
        .to output(/KAMAL_SERVICE=app_mr_5/).to_stdout
    ensure
      ENV.delete('CI_MERGE_REQUEST_IID')
    end

    it 'prints setup when deciding with no matching remote containers' do
      allow($stdin).to receive(:tty?).and_return(false)
      allow($stdin).to receive(:read).and_return("app-web-1\n")

      expect { described_class.run(['decide', '9']) }.to output("setup\n").to_stdout
    end

    it 'dispatches dns-upsert to the resolved DNS provider' do
      fake_provider = instance_double(KamalGitlabReviewApp::Dns::Cloudflare)
      allow(KamalGitlabReviewApp::Dns::Registry).to receive(:resolve).and_return(fake_provider)
      allow(fake_provider).to receive(:upsert_a_record!)
      ENV['REVIEW_TARGET_IP'] = '203.0.113.10'

      expect { described_class.run(['dns-upsert', '3']) }
        .to output(/dns_upsert:mr-3\.review\.example\.com/).to_stdout

      expect(fake_provider).to have_received(:upsert_a_record!)
        .with(name: 'mr-3.review.example.com', ip: '203.0.113.10', ttl: 120)
    ensure
      ENV.delete('REVIEW_TARGET_IP')
    end

    it 'dispatches dns-delete to the resolved DNS provider' do
      fake_provider = instance_double(KamalGitlabReviewApp::Dns::Cloudflare)
      allow(KamalGitlabReviewApp::Dns::Registry).to receive(:resolve).and_return(fake_provider)
      allow(fake_provider).to receive(:delete_record!)

      expect { described_class.run(['dns-delete', '3']) }
        .to output(/dns_delete:mr-3\.review\.example\.com/).to_stdout

      expect(fake_provider).to have_received(:delete_record!).with(name: 'mr-3.review.example.com')
    end
  end

  describe KamalGitlabReviewApp::CLI::Deploy do
    include_context 'with review app env'

    around do |example|
      Dir.mktmpdir do |dir|
        @project_root = dir
        File.write(File.join(dir, 'secrets.review.template'), "RAILS_MASTER_KEY=abc\n")
        example.run
      end
    end

    before do
      ENV['KAMAL_GITLAB_REVIEW_APP_PROJECT_ROOT'] = @project_root
      ENV['CI_MERGE_REQUEST_IID'] = '42'
      ENV['SECRETS_REVIEW_FILE'] = File.join(@project_root, 'secrets.review.template')
      ENV['REVIEW_TARGET_IP'] = '203.0.113.10'

      KamalGitlabReviewApp::Dns::Registry.register(:fake, fake_dns_provider_class)
      ENV['REVIEW_DNS_PROVIDER'] = 'fake'
    end

    after do
      %w[KAMAL_GITLAB_REVIEW_APP_PROJECT_ROOT CI_MERGE_REQUEST_IID SECRETS_REVIEW_FILE
         REVIEW_TARGET_IP REVIEW_DNS_PROVIDER KAMAL_SERVICE GENERAL_HOST DB_HOST].each { |key| ENV.delete(key) }
      KamalGitlabReviewApp::Dns::Registry.reset!
      KamalGitlabReviewApp::Dns::Registry.register(:cloudflare, KamalGitlabReviewApp::Dns::Cloudflare)
    end

    let(:fake_dns_provider_class) do
      Class.new do
        def self.upserts
          @upserts ||= []
        end

        def upsert_a_record!(**kwargs)
          self.class.upserts << kwargs
        end

        def delete_record!(**); end
      end
    end

    it 'writes runtime env, upserts DNS, and runs kamal setup when no remote container matches' do
      commands = []
      runner = lambda { |*cmd| commands << cmd; true }
      container_lister = -> { '' }

      described_class.call(runner:, container_lister:)

      expect(File.read(File.join(@project_root, '.kamal/review.env'))).to include('KAMAL_SERVICE=app_mr_42')
      secrets_path = File.join(@project_root, '.kamal/secrets.review')
      expect(File.read(secrets_path))
        .to eq("RAILS_MASTER_KEY=abc\nGENERAL_HOST=mr-42.review.example.com\nKAMAL_SERVICE=app_mr_42\nDB_HOST=app_mr_42-db\n")
      expect(File.stat(secrets_path).mode & 0o777).to eq(0o600)
      expect(fake_dns_provider_class.upserts).to eq([{ name: 'mr-42.review.example.com', ip: '203.0.113.10', ttl: 120 }])
      expect(commands).to eq([
                                %w[bundle exec kamal registry setup -d review],
                                %w[bundle exec kamal setup -d review]
                              ])
      expect(ENV.fetch('KAMAL_SERVICE')).to eq('app_mr_42')
    end

    it 'runs kamal deploy when a matching remote container already exists' do
      commands = []
      runner = lambda { |*cmd| commands << cmd; true }
      container_lister = -> { "app_mr_42-web-1\n" }

      described_class.call(runner:, container_lister:)

      expect(commands).to eq([
                                %w[bundle exec kamal registry setup -d review],
                                %w[bundle exec kamal deploy -d review]
                              ])
    end

    it 'raises when a kamal command fails (fail loud)' do
      runner = ->(*cmd) { cmd.include?('setup') ? false : true }
      container_lister = -> { '' }

      expect { described_class.call(runner:, container_lister:) }
        .to raise_error(KamalGitlabReviewApp::CLI::Deploy::Error, /Command failed/)
    end

    it 'treats an empty remote container listing as first deploy (setup)' do
      commands = []
      runner = lambda { |*cmd| commands << cmd; true }

      described_class.call(runner:, container_lister: -> { '' })

      expect(commands.last).to eq(%w[bundle exec kamal setup -d review])
    end

    it 'lets the default container lister swallow ssh failures as empty output' do
      allow(Open3).to receive(:capture2).and_raise('unreachable host')

      expect(described_class::DEFAULT_CONTAINER_LISTER.call).to eq('')
    end
  end

  describe KamalGitlabReviewApp::CLI::Stop do
    include_context 'with review app env'

    around do |example|
      Dir.mktmpdir do |dir|
        @project_root = dir
        example.run
      end
    end

    before do
      ENV['KAMAL_GITLAB_REVIEW_APP_PROJECT_ROOT'] = @project_root
      ENV['CI_MERGE_REQUEST_IID'] = '42'
      ENV['REVIEW_ACCESSORIES'] = 'db, redis'
      ENV['REVIEW_TARGET_IP'] = '203.0.113.10'

      KamalGitlabReviewApp::Dns::Registry.register(:fake, fake_dns_provider_class)
      ENV['REVIEW_DNS_PROVIDER'] = 'fake'
    end

    after do
      %w[KAMAL_GITLAB_REVIEW_APP_PROJECT_ROOT CI_MERGE_REQUEST_IID REVIEW_ACCESSORIES
         REVIEW_TARGET_IP REVIEW_DNS_PROVIDER KAMAL_SERVICE GENERAL_HOST DB_HOST].each { |key| ENV.delete(key) }
      KamalGitlabReviewApp::Dns::Registry.reset!
      KamalGitlabReviewApp::Dns::Registry.register(:cloudflare, KamalGitlabReviewApp::Dns::Cloudflare)
    end

    let(:fake_dns_provider_class) do
      Class.new do
        def self.deletes
          @deletes ||= []
        end

        def upsert_a_record!(**); end

        def delete_record!(**kwargs)
          self.class.deletes << kwargs
        end
      end
    end

    it 'removes the app, each accessory, deletes DNS, and runs remote docker cleanup' do
      commands = []
      runner = lambda { |*cmd, **| commands << cmd; true }

      described_class.call(runner:)

      expect(commands).to eq([
                                %w[bundle exec kamal app remove -d review],
                                %w[bundle exec kamal accessory remove db -d review -y],
                                %w[bundle exec kamal accessory remove redis -d review -y],
                                ['ssh', 'deploy@203.0.113.10', 'bash', '-s', '--', 'app_mr_42']
                              ])
      expect(fake_dns_provider_class.deletes).to eq([{ name: 'mr-42.review.example.com' }])
    end

    it 'never raises when every step fails, and reports overall failure' do
      runner = ->(*, **) { false }
      allow(KamalGitlabReviewApp::Dns::Registry).to receive(:resolve).and_raise('dns down')

      result = nil
      expect { result = described_class.call(runner:) }.to output.to_stderr
      expect(result).to be(false)
    end

    it 'returns true when at least one teardown step succeeds' do
      runner = lambda { |*cmd, **| cmd.first != 'bundle' }
      allow(KamalGitlabReviewApp::Dns::Registry).to receive(:resolve).and_raise('dns down')

      result = nil
      expect { result = described_class.call(runner:) }.to output.to_stderr
      expect(result).to be(true)
    end

    it 'still attempts DNS delete and docker cleanup after a kamal command fails' do
      commands = []
      runner = lambda { |*cmd, **|
        commands << cmd
        cmd.first == 'bundle' ? false : true
      }

      expect { described_class.call(runner:) }.to output(/kamal app remove failed/).to_stderr

      expect(fake_dns_provider_class.deletes).to eq([{ name: 'mr-42.review.example.com' }])
      expect(commands).to include(['ssh', 'deploy@203.0.113.10', 'bash', '-s', '--', 'app_mr_42'])
    end

    it 'still runs DNS delete and docker cleanup when project_root cannot be entered' do
      ENV['KAMAL_GITLAB_REVIEW_APP_PROJECT_ROOT'] = File.join(@project_root, 'does-not-exist')
      commands = []
      runner = lambda { |*cmd, **| commands << cmd; true }

      expect { described_class.call(runner:) }.to output(/kamal teardown failed/).to_stderr

      expect(fake_dns_provider_class.deletes).to eq([{ name: 'mr-42.review.example.com' }])
      expect(commands).to eq([['ssh', 'deploy@203.0.113.10', 'bash', '-s', '--', 'app_mr_42']])
    end
  end
end
