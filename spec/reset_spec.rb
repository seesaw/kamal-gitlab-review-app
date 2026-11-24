# frozen_string_literal: true

require 'spec_helper'
require 'kamal_gitlab_review_app/cli'
require 'tmpdir'
require 'yaml'
require 'kamal'

RSpec.describe KamalGitlabReviewApp::CLI::Reset do
  around do |example|
    previous = ENV.to_h
    Dir.mktmpdir do |dir|
      @project_root = dir
      ENV.update('KAMAL_GITLAB_REVIEW_APP_PROJECT_ROOT' => dir,
                 'CI_MERGE_REQUEST_IID' => '42', 'REVIEW_SERVICE_PREFIX' => 'shop_mr',
                 'REVIEW_DOMAIN' => 'review.example.com', 'REVIEW_TARGET_IP' => '203.0.113.10',
                 'SECRETS_REVIEW_FILE' => "#{dir}/secrets", 'REVIEW_RESET_COMMAND' => 'bin/reset-data')
      ENV.delete('REVIEW_RESET_VERSION')
      File.write("#{dir}/secrets", "TOKEN=private")
      FileUtils.mkdir_p("#{dir}/config")
      @config = {
        'service' => '<%= ENV.fetch("KAMAL_SERVICE") %>', 'image' => 'example/shop',
        'servers' => { 'api' => { 'hosts' => ['203.0.113.10'], 'proxy' => false },
                       'worker' => { 'hosts' => ['203.0.113.10'], 'cmd' => 'bin/jobs' } },
        'primary_role' => 'api', 'ssh' => { 'user' => 'deploy' },
        'registry' => { 'username' => 'example', 'password' => 'test' },
        'builder' => { 'arch' => 'amd64' }
      }
      File.write("#{dir}/config/deploy.yml", @config.to_yaml)
      File.write("#{dir}/config/deploy.review.yml", {}.to_yaml)
      example.run
    end
  ensure
    ENV.replace(previous)
  end

  let(:commands) { [] }
  let(:exec_response) { '' }
  let(:responses) do
    {
      version: "abc123\n",
      inventory: [stopped, stopped, stopped.gsub('exited', 'running')],
      exec_inventory: exec_response,
      stop: '', exec: '', start: ''
    }
  end
  let(:runner) do
    lambda do |*command|
      commands << command
      operation = operation_for(command)
      response = responses.fetch(operation)
      response = response.shift if operation == :inventory
      raise KamalGitlabReviewApp::CLI::Reset::Error, 'Command failed: secret output' if response == :failure

      response
    end
  end
  let(:reset) { described_class.new(runner:) }

  def operation_for(command)
    return command.fetch(4).to_sym if command.take(4) == %w[bundle exec kamal app]

    raise "Unexpected command: #{command.inspect}" unless command.first == 'ssh'

    filters = Shellwords.split(command.last)
    filters.any? { |argument| argument.start_with?('name=') } ? :exec_inventory : :inventory
  end

  def command_for(operation)
    commands.find { |command| operation_for(command) == operation }
  end

  def kamal_actions
    commands.filter_map { |command| command.fetch(4) if command.take(4) == %w[bundle exec kamal app] }
  end

  def stopped
    "shop_mr_42-api-review-abc123 exited\nshop_mr_42-worker-review-abc123 exited\n"
  end

  it 'stops, resets once in a new primary role container and starts the captured version' do
    reset.call
    expect(command_for(:stop)).to eq(%w[bundle exec kamal app stop -d review])
    expect(command_for(:exec)).to eq(%w[bundle exec kamal app exec -d review --roles api --primary --version abc123 bin/reset-data])
    expect(command_for(:start)).to eq(%w[bundle exec kamal app start -d review --version abc123])
    expect(commands.map { |command| operation_for(command) }).to eq(
      %i[version inventory stop inventory exec_inventory exec start inventory]
    )
    expect(Shellwords.split(command_for(:inventory).last)).to include('label=service=shop_mr_42', 'label=destination=review')
  end

  %w[running restarting paused].each do |state|
    it "refuses to reset while a writer is #{state}" do
      responses[:inventory][1] = stopped.gsub('exited', state)
      expect { reset.call }.to raise_error(described_class::Error, /abc123/)
      expect(kamal_actions).not_to include('exec', 'start')
    end
  end

  it 'refuses to reset if the independent SSH check fails' do
    responses[:inventory][1] = :failure
    expect { reset.call }.to raise_error(described_class::Error)
    expect(kamal_actions).not_to include('exec', 'start')
  end

  it 'leaves the app stopped after failed seeding and reports a retry version' do
    responses[:exec] = :failure
    expect { reset.call }.to raise_error(described_class::Error, /REVIEW_RESET_VERSION=abc123/)
    expect(kamal_actions).to include('stop', 'exec')
    expect(kamal_actions).not_to include('start')
  end

  it 'refuses ambiguous deployed versions before stopping' do
    responses[:version] = "abc123\ndef456\n"
    expect { reset.call }.to raise_error(described_class::Error)
    expect(kamal_actions).not_to include('stop', 'exec', 'start')
  end

  it 'verifies both role containers before retrying an explicit version' do
    reset.call(version: 'abc123')
    expect(command_for(:version)).to be_nil
    expect(command_for(:exec)).to include('--version', 'abc123')
  end

  it 'refuses a retry version absent from either role' do
    responses[:inventory] = ["shop_mr_42-api-review-abc123 exited\n"]
    expect { reset.call(version: 'abc123') }.to raise_error(described_class::Error)
    expect(kamal_actions).not_to include('stop', 'exec', 'start')
  end

  context 'with an interrupted temporary exec container' do
    %w[running restarting paused].each do |state|
      context "when #{state}" do
        let(:exec_response) { "shop_mr_42-api-review-exec-abc123-a1b2c3 #{state}\n" }

        it 'blocks a new reset before another temporary container starts' do
          expect { reset.call }.to raise_error(described_class::Error, /writers/)
          expect(kamal_actions).not_to include('exec', 'start')
        end

        it 'blocks a retry even when both deployed role containers are stopped' do
          expect { reset.call(version: 'abc123') }.to raise_error(described_class::Error, /writers/)
          expect(kamal_actions).not_to include('exec', 'start')
        end
      end
    end
  end

  context 'with a surviving jobs exec container' do
    let(:exec_response) { "shop_mr_42-worker-review-exec-abc123-a1b2c3 running\n" }

    it 'blocks reset' do
      expect { reset.call }.to raise_error(described_class::Error, /writers/)
    end
  end

  context 'when temporary-container inspection fails' do
    let(:exec_response) { :failure }

    it 'fails closed before resetting' do
      expect { reset.call }.to raise_error(described_class::Error)
      expect(kamal_actions).not_to include('exec', 'start')
    end
  end

  context 'with unrelated or completed temporary containers' do
    let(:exec_response) do
      "shop_mr_420-api-review-exec-abc123-a1b2c3 running\n" \
        "shop_mr_42-api-production-exec-abc123-a1b2c3 running\n" \
        "shop_mr_42-api-review-exec-abc123-a1b2c3 exited\n"
    end

    it 'permits reset and restricts the remote query to this MR and destination' do
      expect { reset.call }.not_to raise_error
      query = command_for(:exec_inventory)
      expect(Shellwords.split(query.last)).to include('name=^/shop_mr_42-.+-review-exec-[a-zA-Z0-9_.-]+-[a-f0-9]{6}$')
    end
  end

  it 'refuses invalid identifiers before any command' do
    expect { ENV['CI_MERGE_REQUEST_IID'] = '0'; reset.call }.to raise_error(described_class::Error)
    expect(commands).to be_empty
  end

  it 'treats a failed SSH subprocess as an error without exposing its output' do
    status = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).with('ssh', 'host').and_return(['secret output', 'secret error', status])
    expect { described_class.capture('ssh', 'host') }.to raise_error(described_class::Error, /Container inspection failed/)
  end

  it 'fails if either role did not restart' do
    responses[:inventory][-1] = stopped
    expect { reset.call }.to raise_error(described_class::Error)
  end

  it 'prepares runtime and secrets without requiring DNS credentials' do
    reset.call
    secrets = File.join(@project_root, '.kamal/secrets.review')
    expect(File.read(secrets)).to include("TOKEN=private\nGENERAL_HOST=mr-42.review.example.com\n", 'KAMAL_SERVICE=shop_mr_42')
    expect(File.stat(secrets).mode & 0o777).to eq(0o600)
    expect(kamal_actions).not_to include('deploy', 'setup', 'remove')
  end

  it 'refuses an absent reset command before stopping the app' do
    ENV.delete('REVIEW_RESET_COMMAND')
    expect { reset.call }.to raise_error(described_class::Error, /REVIEW_RESET_COMMAND/)
    expect(commands).to be_empty
  end

  it 'refuses blank or malformed commands before stopping the app' do
    [' ', "'unterminated"].each do |command|
      ENV['REVIEW_RESET_COMMAND'] = command
      expect { reset.call }.to raise_error(described_class::Error, /command/i)
    end
    expect(commands).to be_empty
  end

  it 'refuses a second application host before any remote command' do
    @config['servers']['worker']['hosts'] << '203.0.113.11'
    File.write(File.join(@project_root, 'config/deploy.yml'), @config.to_yaml)
    expect { reset.call }.to raise_error(described_class::Error, /single host/)
    expect(commands).to be_empty
  end

  it 'refuses a different service before any remote command' do
    @config['service'] = 'production'
    File.write(File.join(@project_root, 'config/deploy.yml'), @config.to_yaml)
    expect { reset.call }.to raise_error(described_class::Error, /service/)
    expect(commands).to be_empty
  end

  it 'refuses a different review target before any remote command' do
    ENV['REVIEW_TARGET_IP'] = '203.0.113.99'
    expect { reset.call }.to raise_error(described_class::Error, /host/)
    expect(commands).to be_empty
  end

  it 'preserves quoted command arguments for Kamal' do
    ENV['REVIEW_RESET_COMMAND'] = 'bin/reset-data "demo data"'
    reset.call
    expect(command_for(:exec).last).to eq('bin/reset-data demo\\ data')
  end

  it 'uses the configured SSH user and port' do
    @config['ssh'] = { 'user' => 'review', 'port' => 2222 }
    File.write(File.join(@project_root, 'config/deploy.yml'), @config.to_yaml)
    reset.call
    expect(command_for(:inventory)[0...-1]).to eq(%w[ssh -o BatchMode=yes -p 2222 review@203.0.113.10])
  end

  it 'rejects unsupported SSH transport options before stopping' do
    @config['ssh']['proxy'] = 'jump.example.com'
    File.write(File.join(@project_root, 'config/deploy.yml'), @config.to_yaml)
    expect { reset.call }.to raise_error(described_class::Error, /SSH/)
    expect(commands).to be_empty
  end

  it 'returns a clean CLI failure for a missing command' do
    ENV.delete('REVIEW_RESET_COMMAND')
    status = nil
    expect { status = KamalGitlabReviewApp::CLI.run(['reset']) }.to output(/REVIEW_RESET_COMMAND/).to_stderr
    expect(status).to eq(1)
  end

  it 'blocks temporary writers belonging to a removed role' do
    responses[:exec_inventory] = "shop_mr_42-old-worker-review-exec-abc123-a1b2c3 running\n"
    expect { reset.call }.to raise_error(described_class::Error, /writers/)
    expect(kamal_actions).not_to include('exec', 'start')
  end

  it 'does not execute reset or restart when stop fails' do
    responses[:stop] = :failure
    expect { reset.call }.to raise_error(described_class::Error, /REVIEW_RESET_VERSION=abc123/)
    expect(kamal_actions).to include('stop')
    expect(kamal_actions).not_to include('exec', 'start')
  end

  it 'rejects an unrecognized container state before stopping' do
    responses[:inventory][0] = "shop_mr_42-api-review-abc123 unknown\n"
    expect { reset.call }.to raise_error(described_class::Error, /inventory/)
    expect(kamal_actions).not_to include('stop', 'exec', 'start')
  end

  it 'fails before remote commands when the secret template is missing' do
    File.unlink(ENV.fetch('SECRETS_REVIEW_FILE'))
    expect { reset.call }.to raise_error(described_class::Error, /runtime files/)
    expect(commands).to be_empty
  end

  it 'accepts a single-role application' do
    @config['servers'].delete('worker')
    File.write(File.join(@project_root, 'config/deploy.yml'), @config.to_yaml)
    responses[:inventory].map! { |response| response.lines.reject { |line| line.include?('-worker-') }.join }
    expect { reset.call }.not_to raise_error
  end

  %i[stop exec start].each do |action|
    it "identifies a failed #{action} without disclosing command details" do
      responses[action] = :failure
      expect { reset.call }.to raise_error(described_class::Error) do |error|
        expect(error.message).to include("Kamal #{action} failed", 'REVIEW_RESET_VERSION=abc123')
        expect(error.message).not_to include('secret output', 'bin/reset-data')
      end
    end
  end

  it 'does not disguise errors in validation as configuration loading failures' do
    allow(Kamal::Configuration).to receive(:create_from).and_wrap_original do |original, **options|
      config = original.call(**options)
      allow(config).to receive(:roles).and_raise(NoMethodError, 'incompatible role API')
      config
    end

    expect { reset.call }.to raise_error(NoMethodError, /incompatible role API/)
    expect(commands).to be_empty
  end

  it 'sanitizes failures evaluating the Kamal configuration' do
    File.write(File.join(@project_root, 'config/deploy.review.yml'), "<%= raise 'secret-value' %>")
    expect { reset.call }.to raise_error(described_class::Error) do |error|
      expect(error.message).to include('Cannot load review Kamal configuration')
      expect(error.message).not_to include('secret-value')
    end
    expect(commands).to be_empty
  end

  it 'does not suggest a previous version after a later version lookup fails' do
    responses[:exec] = :failure
    expect { reset.call }.to raise_error(described_class::Error, /REVIEW_RESET_VERSION=abc123/)
    responses[:version] = "ambiguous\nversions\n"

    expect { reset.call }.to raise_error(described_class::Error) do |error|
      expect(error.message).to include('Expected one explicit deployed version')
      expect(error.message).not_to include('REVIEW_RESET_VERSION')
    end
  end

  it 'tightens existing secret file permissions and replaces stale content' do
    FileUtils.mkdir_p(File.join(@project_root, '.kamal'))
    secret_path = File.join(@project_root, '.kamal/secrets.review')
    File.write(secret_path, 'STALE_SECRET=old')
    File.chmod(0o644, secret_path)

    reset.call

    expect(File.stat(secret_path).mode & 0o777).to eq(0o600)
    expect(File.read(secret_path)).to include("TOKEN=private\n")
    expect(File.read(secret_path)).not_to include('STALE_SECRET')
  end
end
