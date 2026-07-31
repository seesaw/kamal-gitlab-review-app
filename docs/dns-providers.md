# Writing a DNS provider

`kamal-gitlab-review-app` resolves DNS providers through `KamalGitlabReviewApp::Dns::Registry`, keyed by the `REVIEW_DNS_PROVIDER` ENV variable (default `cloudflare`). Any gem or app can register its own provider without touching this gem's code.

## The provider contract

A provider is any class with a no-argument constructor and two instance methods:

```ruby
module KamalGitlabReviewApp
  module Dns
    module Provider
    end
  end
end
```

```text
#upsert_a_record!(name:, ip:, ttl:) -> void
  Create the A record for `name` if it doesn't exist, or update it in place if it does.
  Must be idempotent: calling it twice with the same arguments leaves DNS in the same state.

#delete_record!(name:) -> void
  Delete the A record for `name`. Must be safe to call when the record doesn't exist
  (e.g. return nil / no-op rather than raising).
```

`KamalGitlabReviewApp::Dns::Provider` is an empty marker module included by adapters for documentation purposes; it declares no methods and is **not** required for registration to work — the registry only cares that the class responds to the two methods above.

Raise `KamalGitlabReviewApp::Dns::Error` (or let your own errors propagate) on unrecoverable failures. Deploy is fail-loud, so provider errors during `upsert_a_record!` will abort the CI job; provider errors during `delete_record!` (called from `stop`) are caught and logged by `CLI::Stop`, so raising is safe there too.

## Registering a provider

Call `KamalGitlabReviewApp::Dns::Registry.register(name, klass)` before `Dns::Registry.resolve` is called (typically at `require` time of your adapter):

```ruby
# my_dns_gem/lib/my_dns_gem.rb
require 'kamal_gitlab_review_app'

module MyDnsGem
  class Provider
    include KamalGitlabReviewApp::Dns::Provider

    def upsert_a_record!(name:, ip:, ttl:)
      # call your DNS API
    end

    def delete_record!(name:)
      # call your DNS API
    end
  end
end

KamalGitlabReviewApp::Dns::Registry.register(:my_dns, MyDnsGem::Provider)
```

Then, in the host app / CI job:

```bash
export REVIEW_DNS_PROVIDER=my_dns
```

If `REVIEW_DNS_PROVIDER` doesn't match a registered key, `Dns::Registry.resolve` raises `KamalGitlabReviewApp::Dns::Error` listing the registered provider names.

## Reference implementation

[`KamalGitlabReviewApp::Dns::Cloudflare`](../lib/kamal_gitlab_review_app/dns/cloudflare.rb) is the Cloudflare adapter shipped with this gem (registered as `:cloudflare` by default) and is the best example to copy from. It reads `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ZONE_ID` from `ENV` and talks to the Cloudflare API v4 over `Net::HTTP`.
