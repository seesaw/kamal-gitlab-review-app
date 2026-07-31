# frozen_string_literal: true

require_relative 'cli/deploy'
require_relative 'cli/stop'

module KamalGitlabReviewApp
  module CLI
    USAGE = <<~USAGE
      Usage: kamal-gitlab-review-app <command> [args...]

      Commands:
        deploy              Deploy or setup the MR review app
        stop                Tear down the MR review app (best-effort)
        runtime-env [IID]   Print runtime env for an MR IID
        decide [IID]        Decide setup vs deploy from remote container list (stdin)
        dns-upsert [IID]    Upsert DNS record for an MR IID
        dns-delete [IID]    Delete DNS record for an MR IID
        docker-cleanup [IID]  Remote Docker cleanup for an MR IID (debug)

      IID defaults to CI_MERGE_REQUEST_IID when omitted.
    USAGE

    module_function

    def run(argv)
      command, *args = argv

      case command
      when nil, '', '-h', '--help', 'help'
        puts USAGE
        0
      when 'deploy'
        run_deploy
      when 'stop'
        Stop.call ? 0 : 1
      when 'runtime-env'
        print_runtime_env(args)
        0
      when 'decide'
        print_decision(args)
        0
      when 'dns-upsert'
        upsert_dns(args)
        0
      when 'dns-delete'
        delete_dns(args)
        0
      when 'docker-cleanup'
        KamalGitlabReviewApp::Remote::DockerCleanup.call(iid: mr_iid(args))
        0
      else
        warn "Unknown command: #{command.inspect}"
        warn USAGE
        1
      end
    end

    def run_deploy
      Deploy.call
      0
    rescue Deploy::Error, KeyError, KamalGitlabReviewApp::Dns::Error => e
      warn "kamal-gitlab-review-app deploy: #{e.message}"
      1
    end

    def mr_iid(args)
      args.fetch(0) { ENV.fetch('CI_MERGE_REQUEST_IID') }
    end

    def print_runtime_env(args)
      KamalGitlabReviewApp::RuntimeEnv.to_h(iid: mr_iid(args)).sort.each do |key, value|
        puts "#{key}=#{value}"
      end
    end

    def print_decision(args)
      container_names = $stdin.tty? ? [] : $stdin.read.split("\n")
      puts KamalGitlabReviewApp::LifecycleDecider.call(iid: mr_iid(args), container_names:)
    end

    def upsert_dns(args)
      host = KamalGitlabReviewApp::Naming.for_mr(iid: mr_iid(args)).fetch(:host)
      ip = ENV.fetch('REVIEW_TARGET_IP')
      ttl = ENV.fetch('REVIEW_DNS_TTL', '120').to_i

      KamalGitlabReviewApp::Dns::Registry.resolve.upsert_a_record!(name: host, ip:, ttl:)
      puts "dns_upsert:#{host}"
    end

    def delete_dns(args)
      host = KamalGitlabReviewApp::Naming.for_mr(iid: mr_iid(args)).fetch(:host)

      KamalGitlabReviewApp::Dns::Registry.resolve.delete_record!(name: host)
      puts "dns_delete:#{host}"
    end
  end
end
