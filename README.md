# kamal-gitlab-review-app

A gem for deploying and tearing down **per-Merge-Request review apps** on GitLab using [Kamal](https://kamal-deploy.org/), with pluggable DNS.

Each MR gets an isolated environment with a dedicated hostname (`mr-<iid>.<review-domain>`), a dedicated database accessory, and a lifecycle driven manually or automatically from the GitLab pipeline.

The gem **does not require Rails**: configuration is entirely ENV-driven, so it also works for non-Rails projects deployed with Kamal.

## Install

### 1. Add the gem to your Gemfile

```ruby
gem 'kamal'
gem 'kamal-gitlab-review-app' # or: git: 'https://github.com/seesaw/kamal-gitlab-review-app'
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
