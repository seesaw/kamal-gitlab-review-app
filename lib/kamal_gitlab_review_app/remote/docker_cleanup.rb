# frozen_string_literal: true

require 'tempfile'

module KamalGitlabReviewApp
  module Remote
    # Removes leftover containers/volumes/images/dirs on the review host that Kamal's own
    # teardown (`kamal app remove`, `kamal accessory remove`) may miss (basecamp/kamal#516).
    # Ported from the former ci/cleanup_docker.sh remote heredoc.
    #
    # Matching is delimiter-aware (same idea as LifecycleDecider): prefix `app_mr_1` must
    # not match `app_mr_10`.
    class DockerCleanup
      REMOTE_SCRIPT = <<~'REMOTE'
        set -euo pipefail
        SERVICE_PREFIX="$1"

        matches_service_resource() {
          case "$1" in
            "${SERVICE_PREFIX}"|"${SERVICE_PREFIX}-"*|"${SERVICE_PREFIX}_"* ) return 0 ;;
            *) return 1 ;;
          esac
        }

        matches_service_image() {
          case "$1" in
            "${SERVICE_PREFIX}:"*|"${SERVICE_PREFIX}@"*|*/"${SERVICE_PREFIX}:"*|*/"${SERVICE_PREFIX}@"* ) return 0 ;;
            *) return 1 ;;
          esac
        }

        docker ps -a --format '{{.Names}}' | while read -r container; do
          if matches_service_resource "${container}"; then
            docker rm -f "${container}" || true
          fi
        done

        docker volume ls --format '{{.Name}}' | while read -r volume; do
          if matches_service_resource "${volume}"; then
            docker volume rm "${volume}" || true
          fi
        done

        docker image ls --format '{{.Repository}}:{{.Tag}}' | while read -r image; do
          if matches_service_image "${image}"; then
            docker image rm "${image}" || true
          fi
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
