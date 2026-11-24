# frozen_string_literal: true

require 'open3'
require 'shellwords'
require_relative '../runtime_files'

module KamalGitlabReviewApp
  module CLI
    class Reset
      class Error < StandardError; end

      def self.capture(*command)
        stdout, _stderr, status = Open3.capture3(*command)
        raise Error, "#{command.first == 'ssh' ? 'Container inspection' : 'Kamal command'} failed; inspect the review host" unless status.success?

        stdout
      rescue SystemCallError
        raise Error, 'Unable to execute reset command; check SSH and Kamal installation'
      end

      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(runner: self.class.method(:capture))
        @runner = runner
      end

      def call(version: ENV['REVIEW_RESET_VERSION'])
        iid = ENV.fetch('CI_MERGE_REQUEST_IID')
        raise Error, 'Invalid merge request IID' unless iid.match?(/\A[1-9]\d*\z/)

        @command = reset_command
        Dir.chdir(ENV.fetch('KAMAL_GITLAB_REVIEW_APP_PROJECT_ROOT', Dir.pwd)) do
          runtime = RuntimeFiles.prepare(iid:)
          configure(runtime.fetch('KAMAL_SERVICE'))
          reset(version)
        end
      rescue KeyError
        raise Error, 'Missing required review environment configuration'
      rescue SystemCallError
        raise Error, 'Unable to prepare review runtime files; check project root and secrets file'
      end

      private

      def reset_command
        command = ENV['REVIEW_RESET_COMMAND'].to_s
        arguments = Shellwords.split(command)
        raise Error, 'REVIEW_RESET_COMMAND must specify an explicit reset command' if arguments.empty? || arguments.first.empty?

        arguments.shelljoin
      rescue ArgumentError
        raise Error, 'Invalid REVIEW_RESET_COMMAND quoting'
      end

      def configure(service)
        config = load_review_config
        host = validate_review_target!(config, service:)

        @ssh = ssh_command(config, host:)
        @roles = config.roles.map { |role| role.name.to_s }
        @primary_role = config.primary_role_name
        @service = service
      end

      def load_review_config
        require 'kamal'
        Kamal::Configuration.create_from(config_file: Pathname.new('config/deploy.yml'), destination: 'review')
      rescue LoadError, StandardError
        raise Error, 'Cannot load review Kamal configuration; verify config/deploy.review.yml and Kamal installation'
      end

      def validate_review_target!(config, service:)
        raise Error, 'Review service does not match MR naming' unless config.service == service

        hosts = config.roles.flat_map(&:hosts).uniq
        unless hosts == [ENV.fetch('REVIEW_TARGET_IP')]
          raise Error, 'Reset requires a single host matching REVIEW_TARGET_IP'
        end
        unless config.roles.any? { |role| role.name == config.primary_role_name }
          raise Error, 'Reset requires a configured primary role'
        end

        hosts.first
      end

      def ssh_command(config, host:)
        ssh = config.raw_config.ssh || {}
        unless (ssh.keys.map(&:to_s) - %w[user port log_level]).empty?
          raise Error, 'Reset supports direct SSH with user and port only'
        end
        user = config.ssh.user
        unless user.match?(/\A[a-zA-Z0-9_.-]+\z/) && host.match?(/\A[a-zA-Z0-9.-]+\z/)
          raise Error, 'Invalid SSH target'
        end

        ['ssh', '-o', 'BatchMode=yes', '-p', config.ssh.port.to_s, "#{user}@#{host}"]
      end

      def reset(requested_version)
        version = validated_version(requested_version || kamal('version', '--roles', @primary_role, '--primary', '--quiet').strip)
        verify_roles!(inventory, version:)
        kamal('stop')
        ensure_stopped!
        kamal('exec', '--roles', @primary_role, '--primary', '--version', version, @command)
        kamal('start', '--version', version)
        verify_roles!(inventory, version:, running: true)
      rescue Error => e
        raise Error, "#{e.message}. No automatic recovery; retry reset with REVIEW_RESET_VERSION=#{version}" if version

        raise
      end

      def validated_version(version)
        raise Error, 'Expected one explicit deployed version' unless version.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/)

        version
      end

      def kamal(action, *args)
        @runner.call('bundle', 'exec', 'kamal', 'app', action, '-d', 'review', *args)
      rescue Error
        raise Error, "Kamal #{action} failed; inspect the review host"
      end

      def inventory
        containers_matching("label=service=#{@service}", 'label=destination=review')
      end

      def exec_inventory
        # Exec containers have no destination label. Include old roles as well.
        pattern = "#{Regexp.escape(@service)}-.+-review-exec-[a-zA-Z0-9_.-]+-[a-f0-9]{6}"
        containers_matching("name=^/#{pattern}$").select { |name, _state| name.match?(/\A#{pattern}\z/) }
      end

      def containers_matching(*filters)
        command = ['docker', 'ps', '--all', *filters.flat_map { |filter| ['--filter', filter] }, '--format', '{{.Names}} {{.State}}']
        @runner.call(*@ssh, command.shelljoin).lines.to_h do |line|
          fields = line.strip.split
          unless fields.length == 2 && %w[created running paused restarting removing exited dead].include?(fields.last)
            raise Error, 'Invalid container inventory'
          end

          fields
        end
      end

      def ensure_stopped!
        states = inventory.values + exec_inventory.values
        unless states.all? { |state| %w[exited dead].include?(state) }
          raise Error, 'Review writers are still active; investigate any surviving exec container before retrying'
        end
      end

      def verify_roles!(containers, version:, running: false)
        valid = @roles.all? do |role|
          state = containers["#{@service}-#{role}-review-#{version}"]
          running ? state == 'running' : !state.nil?
        end
        raise Error, 'Expected role version containers are missing or not running' unless valid
      end
    end
  end
end
