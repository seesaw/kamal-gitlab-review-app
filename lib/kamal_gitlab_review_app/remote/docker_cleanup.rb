# frozen_string_literal: true

require 'tempfile'

module KamalGitlabReviewApp
  module Remote
    # Removes leftover containers/volumes/images/dirs on the review host that Kamal's own
    # teardown (`kamal app remove`, `kamal accessory remove`) may miss (basecamp/kamal#516).
    # Ported from the former ci/cleanup_docker.sh remote heredoc.
    class DockerCleanup
      REMOTE_SCRIPT = <<~'REMOTE'
        set -euo pipefail
        SERVICE_PREFIX="$1"

        docker ps -a --format '{{.Names}}' | while read -r container; do
          case "${container}" in
            "${SERVICE_PREFIX}"* ) docker rm -f "${container}" || true ;;
          esac
        done

        docker volume ls --format '{{.Name}}' | while read -r volume; do
          case "${volume}" in
            "${SERVICE_PREFIX}"* ) docker volume rm "${volume}" || true ;;
          esac
        done

        docker image ls --format '{{.Repository}}:{{.Tag}}' | while read -r image; do
          case "${image}" in
            *"${SERVICE_PREFIX}"* ) docker image rm "${image}" || true ;;
          esac
        done

        # Kamal accessory host dirs (e.g. app_mr_42-db). `kamal accessory remove` runs plain
        # `rm -rf`, which fails on Postgres data/ owned by the container UID (Permission
        # denied). Wipe contents as root via Docker, then remove the deploy-owned parent dir.
        for dir in "${SERVICE_PREFIX}"-*; do
          [ -d "${dir}" ] || continue
          docker run --rm -v "${PWD}/${dir}:/wipe" alpine:3 \
            sh -c 'find /wipe -mindepth 1 -delete' || true
          rm -rf "${dir}" || true
        done
      REMOTE

      def self.call(iid:, ssh_user: ENV.fetch('REVIEW_SSH_USER', 'deploy'),
                    target_ip: ENV.fetch('REVIEW_TARGET_IP'), runner: method(:system))
        service_prefix = "#{KamalGitlabReviewApp::Env.service_prefix}_#{iid}"

        Tempfile.create('kamal-gitlab-review-app-docker-cleanup') do |script_file|
          script_file.write(REMOTE_SCRIPT)
          script_file.flush

          ok = runner.call('ssh', "#{ssh_user}@#{target_ip}", 'bash', '-s', '--', service_prefix,
                           in: script_file.path)
          raise "remote docker cleanup failed for #{service_prefix}" unless ok
        end
      end
    end
  end
end
