# LiteLLM declarative configuration

Models, credentials, organizations, teams, users, keys, budgets, tags,
fallbacks and prompts, reconciled from this module by Crossplane's
`provider-terraform`.

## Why this is not in the Helm values

A model declared in `proxy_config.model_list` exists only in the config file.
The rest of LiteLLM cannot see it: no access group, no team scoping, no budget,
no per-model rate limit, not editable from the UI. Those objects live in
Postgres, and the API that writes them is the one this provider calls.

So `store_model_in_db: true`, `model_list: []` in the values, and the catalogue
here. The proxy re-reads it every 30s
(`proxy_config_reload_interval_seconds`), so an apply needs no rollout.

## Wiring

```
providerconfig/providerconfig.yaml   terraform{} + provider{} + kubernetes backend
providerconfig/externalsecret.yaml   master key -> litellm.auto.tfvars.json
providerconfig/workspace.yaml        points here over git, publishes outputs
../terraformrc.yaml                  network mirror at s3.lab.com
```

The `terraform`, `provider` and `backend` blocks are deliberately absent from
this directory — `provider-terraform` writes them in from the ProviderConfig,
and declaring them here too is a duplicate block at `init`.

Terraform authenticates with the master key; creating models and teams is
admin-only.

## Before the first apply

1. **Mirror the provider.** `../terraformrc.yaml` points at the S3 network
   mirror, not `registry.terraform.io`. `ncecere/litellm 2.0.1` is listed in
   `scripts/terraform/providers.txt` but has to be pushed:
   `./scripts/terraform/mirror.sh` (answer `y` at the upload prompt).
2. **Sync the chart first.** The Workspace calls the LiteLLM API, so the proxy
   must be running before the first plan. It starts fine with an empty
   catalogue.

## Files

| File | |
|---|---|
| `models.tf` | The catalogue and its access groups |
| `credentials.tf` | Backend credentials, referenced by name from models |
| `organizations.tf` `teams.tf` `users.tf` | Hierarchy, budgets, membership |
| `keys.tf` | Service-account keys for in-cluster workloads |
| `budgets.tf` `tags.tf` | Reusable spending tiers, cost attribution |
| `fallbacks.tf` `prompts.tf` | Global fallback chains, managed prompts |
| `examples.tf.disabled` | MCP servers, agents, guardrails, vector stores, search tools — validated but inert until a backend exists |

Access is layered: `organization -> team -> key -> tag`, first refusal wins.
Model access is separate — a team's `models` list holds **access group names**,
so adding a model to `frontier-models` grants it to every team with that group.

## Handing keys to consumers

```bash
kubectl -n litellm get secret litellm-tf-outputs \
  -o jsonpath='{.data.service_account_keys}' | base64 -d | jq
```

Three apps still hardcode a LiteLLM key in git — `openwebui`
(`openaiApiKeys`), `holmesgpt` (`OPENAI_API_KEY`), `open-design`
(`ANTHROPIC_AUTH_TOKEN`). Those keep working; the ones here are extra rows, not
replacements. To cut one over: PushSecret `litellm-tf-outputs` into Vault, add
an ExternalSecret in `ai`, repoint the app, then delete the literal.

## Checking a change

The Workspace applies whatever `main` holds.

```bash
terraform fmt -check .

# validate needs the provider block the ProviderConfig normally supplies
mkdir -p /tmp/litellm-tfval && cp *.tf /tmp/litellm-tfval/
cat > /tmp/litellm-tfval/_provider.tf <<'EOF'
terraform {
  required_providers {
    litellm = {
      source  = "ncecere/litellm"
      version = "2.0.1"
    }
  }
}
variable "litellm_api_key" {
  type    = string
  default = "sk-dummy"
}
provider "litellm" {
  api_base = "http://127.0.0.1:4000"
  api_key  = var.litellm_api_key
}
EOF
cd /tmp/litellm-tfval && terraform init && terraform validate
```

```bash
kubectl describe workspace.tf.upbound.io litellm
```

## Two traps

**`LITELLM_SALT_KEY` is permanent.** It encrypts `credential_values` at rest;
rotating it leaves every stored credential undecryptable. The `litellm-salt`
PushSecret uses `updatePolicy: IfNotExists` for that reason.

**`additional_litellm_params` keys cannot be removed by editing.**
`/model/update` merges `litellm_params`, so deleting a key stops sending it but
leaves it set upstream. Use
`terraform apply -replace='litellm_model.claude_opus_4_8'`.
