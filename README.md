# kamal-gitlab-review-app

Gem per deployare e distruggere **review app per Merge Request** su GitLab usando [Kamal](https://kamal-deploy.org/) e DNS Cloudflare.

Ogni MR ottiene un ambiente isolato con hostname dedicato (`mr-<iid>.<review-domain>`), database dedicato e lifecycle manuale/automatico da pipeline GitLab.

La gem **non richiede Rails**: la configurazione avviene solo via variabili d'ambiente (adatta anche a progetti non-Rails che usano Kamal).

## Installazione

### 1. Aggiungi la gem al Gemfile

```ruby
gem 'kamal-gitlab-review-app' # or: git: 'https://github.com/seesaw/kamal-gitlab-review-app'
```

Poi:

```bash
bundle install
```

### 2. Genera i file di progetto (opzionale, se usi Rails)

```bash
bin/rails generate kamal_gitlab_review_app:install
```

Genera:

- `config/deploy.review.yml` (template minimale Kamal destination)
- `bin/review-apps` (wrapper verso `bundle exec kamal-gitlab-review-app`)

In alternativa copia a mano `bin/review-apps` e il template `deploy.review.yml` dalla gem.

Personalizza `config/deploy.review.yml` con secrets, ruoli (`jobs`), volumi e accessory specifici della tua app.

### 3. Configura naming via ENV

| Variabile | Default | Descrizione |
|-----------|---------|-------------|
| `REVIEW_DOMAIN` | *(required)* | Dominio review (es. `review.example.com`) |
| `REVIEW_SERVICE_PREFIX` | `app_mr` | Prefisso service/container Kamal |
| `REVIEW_ENVIRONMENT_PREFIX` | `review/mr` | Prefisso environment GitLab |
| `REVIEW_HOST_LABEL_PREFIX` | `mr` | Prefisso label host (`mr-<iid>.…`) |

## Variabili GitLab CI richieste

| Variabile | Tipo | Descrizione |
|-----------|------|-------------|
| `SECRETS_REVIEW_FILE` | File | Secrets Kamal condivisi per tutte le review app |
| `CLOUDFLARE_API_TOKEN` | Masked | Token API Cloudflare |
| `CLOUDFLARE_ZONE_ID` | Masked | Zone ID Cloudflare |
| `REVIEW_TARGET_IP` | Variable | IP host deploy (DNS + SSH lifecycle check) |
| `REVIEW_DNS_TTL` | Variable | TTL DNS (default `120`) |
| `REVIEW_DOMAIN` | Variable | Dominio review |
| `REVIEW_SERVICE_PREFIX` | Variable | Prefisso service |

## Snippet `.gitlab-ci.yml`

```yaml
deploy_review:
  stage: deploy # or your stage
  needs: [] # can be started anytime without waiting the CI (customize with your needings)
  variables:
    REVIEW_TARGET_IP: "203.0.113.10"
    REVIEW_DNS_TTL: "120"
    REVIEW_DOMAIN: "review.example.com"
    REVIEW_SERVICE_PREFIX: "myapp_mr"
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

1. **Primo deploy MR**: upsert DNS → check container remoti via SSH → `kamal setup -d review`
2. **Redeploy MR**: upsert DNS → `kamal deploy -d review`
3. **Stop**: `kamal app remove` → delete DNS → cleanup Docker remoto mirato al service MR

## CLI

Configurazione solo via ENV (nessun boot Rails):

```bash
REVIEW_DOMAIN=review.example.com \
REVIEW_SERVICE_PREFIX=myapp_mr \
  bin/review-apps runtime-env 123

bin/review-apps deploy
bin/review-apps stop
bin/review-apps decide 123
bin/review-apps dns-upsert 123
bin/review-apps dns-delete 123
```

Equivalente diretto:

```bash
bundle exec kamal-gitlab-review-app deploy
```

## Test

Dalla directory della gem:

```bash
bundle install
bundle exec rspec
```
