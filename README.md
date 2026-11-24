# kamal-gitlab-review-app

A gem for deploying and tearing down **per-Merge-Request review apps** on GitLab using [Kamal](https://kamal-deploy.org/), with pluggable DNS.

Each MR gets an isolated environment with a dedicated hostname (`mr-<iid>.<review-domain>`), a dedicated database accessory, and a lifecycle driven manually or automatically from the GitLab pipeline.

The gem **does not require Rails**: configuration is entirely ENV-driven, so it also works for non-Rails projects deployed with Kamal.

## Install

### 1. Add the gem to your Gemfile

```ruby
gem 'kamal'
gem 'kamal-gitlab-review-app'
```

Then:

```bash
bundle install
```

`kamal` must be available via `bundle exec` in the host project — this gem shells out to it during deploy/stop.

### 2. Generate project files (optional, Rails only)

```bash
bin/rails generate kamal_gitlab_review_app:install
```

This generates:

- `config/deploy.review.yml` — a minimal Kamal destination template
- `bin/review-apps` — a wrapper around `bundle exec kamal-gitlab-review-app`

Without Rails, copy `bin/review-apps` and the `deploy.review.yml` template from the gem by hand.

Customize `config/deploy.review.yml` with your app's secrets, roles (`servers`), volumes, and accessories.

## Configuration (ENV)

All configuration is read from `ENV` — there is no `Configuration` object and no initializer.

| Variable | Default | Description |
|----------|---------|-------------|
| `REVIEW_DOMAIN` | *(required)* | Review domain (e.g. `review.example.com`) |
| `REVIEW_SERVICE_PREFIX` | `app_mr` | Kamal service/container name prefix |
| `REVIEW_ENVIRONMENT_PREFIX` | `review/mr` | GitLab environment name prefix |
| `REVIEW_HOST_LABEL_PREFIX` | `mr` | Host label prefix (`mr-<iid>.…`) |
| `REVIEW_DNS_PROVIDER` | `cloudflare` | Registered DNS provider key (see [docs/dns-providers.md](docs/dns-providers.md)) |
| `REVIEW_ACCESSORIES` | `db` | Comma-separated Kamal accessory names to remove on stop; `none` or empty means no accessories |
| `REVIEW_DB_ACCESSORY` | first accessory | Accessory name used for `DB_HOST` (`#{service}-#{accessory}`). Set when the DB accessory is not first in `REVIEW_ACCESSORIES` |
| `REVIEW_SSH_USER` | `deploy` | SSH user for remote lifecycle checks and Docker cleanup |
| `REVIEW_TARGET_IP` | *(required)* | Review host IP (DNS target + SSH lifecycle checks) |
| `REVIEW_DNS_TTL` | `120` | DNS record TTL, in seconds |
| `CI_MERGE_REQUEST_IID` | *(required)* | GitLab MR IID; used to derive all per-MR names |
| `KAMAL_GITLAB_REVIEW_APP_PROJECT_ROOT` | current dir | Directory containing `.kamal/` and `config/deploy.review.yml` |
| `SECRETS_REVIEW_FILE` | *(required for deploy)* | Path to a secrets template copied to `.kamal/secrets.review` (mode `0600`); per-MR runtime vars are appended |

DNS-provider-specific variables (e.g. `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ZONE_ID`) are documented per-provider in [docs/dns-providers.md](docs/dns-providers.md).

## `.gitlab-ci.yml` snippet

```yaml
deploy_review:
  stage: deploy # or your stage
  needs: [] # can be started anytime without waiting the CI (customize with your needings)
  variables:
    REVIEW_TARGET_IP: "203.0.113.10"
    REVIEW_DNS_TTL: "120"
    REVIEW_DOMAIN: "review.example.com"
    REVIEW_SERVICE_PREFIX: "myapp_mr"
    # REVIEW_DNS_PROVIDER: "cloudflare"
    # REVIEW_ACCESSORIES: "db,redis"
  environment:
    name: review/mr-$CI_MERGE_REQUEST_IID
    url: https://mr-$CI_MERGE_REQUEST_IID.review.example.com
    on_stop: stop_review
  script:
    - bin/review-apps deploy
  rules:
    # and your rules
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event" && $CI_MERGE_REQUEST_IID'
      when: manual

stop_review:
  stage: deploy # or your stage
  needs: [] # can be started anytime without waiting the CI (customize with your needings)
  environment:
    name: review/mr-$CI_MERGE_REQUEST_IID
    action: stop
  script:
    - bin/review-apps stop
  rules:
    # and your rules
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event" && $CI_MERGE_REQUEST_IID'
      when: manual
      allow_failure: true

stop_review_on_merge_or_close:
  stage: deploy # or your stage
  needs: [] # can be started anytime without waiting the CI (customize with your needings)
  environment:
    name: review/mr-$CI_MERGE_REQUEST_IID
    action: stop
  script:
    - bin/review-apps stop
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event" && ($CI_MERGE_REQUEST_STATE == "merged" || $CI_MERGE_REQUEST_STATE == "closed")'
      when: on_success
    - when: never
```

## Resetting review data

`bin/review-apps reset` stops the deployed application, runs an explicitly configured
command once in a temporary container of the **deployed version**, then restarts
that version only after success. It does not deploy the pipeline commit, change
DNS, remove accessories, or choose a database reset strategy.

```yaml
reset_review:
  extends: .review_manual_job # your existing deployment prerequisites and variables
  resource_group: review-mr-$CI_MERGE_REQUEST_IID
  variables:
    REVIEW_RESET_COMMAND: "bin/rails review_apps:reset"
  environment:
    name: review/mr-$CI_MERGE_REQUEST_IID
    action: prepare
  script:
    - bin/review-apps reset
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event" && $CI_MERGE_REQUEST_IID'
      when: manual
      allow_failure: true
```

Use the **same resource group** on deploy, stop, and reset jobs. Keep your normal
branch exclusions. CI serialization does not protect against concurrent manual
Kamal commands; do not run them during reset.

The application must supply the reset command in the deployed image and guard its
own destructive operations (review marker, environment, and every database or
external service it touches). For example, a Rails task can validate isolation,
truncate databases, and invoke the application's seed mechanism. Rails and SeedFu
are not required by this gem. External storage cleanup is the application's policy.

### Requirements and configuration

- `REVIEW_RESET_COMMAND` is required, with no destructive default. It is parsed as
  shell words and passed as escaped arguments; shell expansion, pipes and redirects
  are not interpreted. Use a checked-in script for compound operations.
- `SECRETS_REVIEW_FILE`, `CI_MERGE_REQUEST_IID`, `REVIEW_DOMAIN` and
  `REVIEW_TARGET_IP` are required, as for deploy. Runtime files are prepared using
  the same naming and secret handling as deploy. No DNS API credentials are needed.
- Kamal 2.11 is tested. Kamal must be in the application's bundle; reset loads its
  configuration API without booting Rails.
- The effective `review` service must match the gem's MR naming. Roles and primary
  role come from the merged Kamal configuration, not fixed `web`/`jobs` names.
- All application roles must run on one host equal to `REVIEW_TARGET_IP`.
  Multi-host applications are rejected before any remote operation.
- Inspection uses the Kamal SSH user and port. This initial version supports direct
  SSH with normal OpenSSH authentication only; explicit Kamal keys, proxies and
  other custom transport options are rejected before stopping anything.

### Failure and recovery

SSH or inventory errors abort the operation. Existing temporary exec containers,
including those from removed roles, block reset while active. A failed reset leaves
the app stopped: there is intentionally no automatic restart over partial data.
Truncation and seeding are **not** made atomic by the gem; the command must support
recovery from partial work.

The error reports `REVIEW_RESET_VERSION=<version>`. After resolving the cause,
retry the job with that variable; all configured role containers must still exist
for that version. If a CI job or SSH session was interrupted, its remote exec
container may still be running: inspect it and wait for completion before retrying.
For a code fix, deploy the corrected image first, then reset without a stale version
override. An image without the reset command fails and leaves the app stopped.

Remote command output is suppressed in CI to avoid leaking secrets. Diagnose
failures on the review host. Container naming follows Kamal 2; revalidate the reset
checks when upgrading Kamal.

## Lifecycle

1. **First deploy for an MR**: upsert DNS → check remote containers over SSH → `kamal setup -d review`
2. **Redeploy for an MR**: upsert DNS → `kamal deploy -d review`
3. **Stop**: `kamal app remove` → remove each configured accessory → delete DNS → remote Docker cleanup scoped to the MR's service

Deploy is **fail loud**: any failed step (writing runtime env, DNS upsert, `kamal setup`/`deploy`, etc.) aborts with a non-zero exit and a short message on stderr.

Stop is **best-effort**: every step is independent — a failure in one (e.g. Kamal app already removed, DNS record already gone) is logged to stderr and does not prevent the remaining steps from running. Exit `0` if at least one top-level step succeeded; exit `1` only when every step failed. Keep `allow_failure: true` on the GitLab `stop_review` job.

Runtime env written to `.kamal/review.env` (and appended to `.kamal/secrets.review`) includes `GENERAL_HOST`, `KAMAL_SERVICE`, and `DB_HOST` when a DB accessory is configured. With `REVIEW_ACCESSORIES=none`, `DB_HOST` is omitted.

> **SSH-failure caveat**: the remote `docker ps` check used to decide `setup` vs `deploy` treats any SSH/connection failure as "no containers found", which means the deploy falls back to `kamal setup`. This is intentional — a brand-new host has no containers yet — but it also means a genuinely broken SSH connection silently triggers `setup` instead of failing. Check the CI logs if a deploy runs `setup` unexpectedly.

## CLI

Configuration is ENV-only (no Rails boot required):

```bash
REVIEW_DOMAIN=review.example.com \
REVIEW_SERVICE_PREFIX=myapp_mr \
  bin/review-apps runtime-env 123

bin/review-apps deploy
bin/review-apps stop
bin/review-apps decide 123
bin/review-apps dns-upsert 123
bin/review-apps dns-delete 123
bin/review-apps docker-cleanup 123 # debug CLI; also runs automatically as part of `stop`
```

Equivalent direct invocation:

```bash
bundle exec kamal-gitlab-review-app deploy
```

## Writing a custom DNS provider

DNS providers are pluggable — see [docs/dns-providers.md](docs/dns-providers.md) for the provider contract and how to register your own from an external gem. Cloudflare (`KamalGitlabReviewApp::Dns::Cloudflare`) ships as the reference implementation.

## Tests

From the gem directory:

```bash
bundle install
bundle exec rspec
```
