# Changelog

## 0.1.1

- Fix remote Docker cleanup matching so `app_mr_1` no longer deletes `app_mr_10` resources.
- Derive `DB_HOST` from `REVIEW_ACCESSORIES` / `REVIEW_DB_ACCESSORY` (omit when accessories are `none`).
- Harden Cloudflare DNS client: HTTP timeouts, status checks, and `Dns::Error` wrapping for network/parse failures.
- Write `.kamal/secrets.review` with mode `0600`.
- CLI: show usage when no command is given; return exit `1` with a clean message on deploy failures.
- Stop returns non-zero when every teardown step fails (still best-effort per step; use `allow_failure: true` in GitLab).

## 0.1.0

- Initial public extraction from an internal project vendored gem.
- GitLab MR review-app lifecycle helpers for Kamal (deploy/stop, DNS, naming).
- Pluggable DNS registry with Cloudflare reference provider.
- ENV-only configuration (no Rails initializer).
- Ruby CLI (`kamal-gitlab-review-app`) with thin shell wrappers for CI.
