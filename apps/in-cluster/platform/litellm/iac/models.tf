# max_parallel_requests has no provider argument, so it rides in
# additional_litellm_params, where ../model_concurrency_limiter.py reads it back
# off the router. Removing a key from that map stops sending it but does not
# unset it upstream — /model/update merges litellm_params, so use -replace.
#
# Costs are Anthropic list prices. cli-proxy-api is subscription-backed, so no
# invoice tracks them; they give budgets something to meter.

resource "litellm_model" "qwen3_0_6b" {
  model_name          = "qwen3:0.6b"
  custom_llm_provider = "ollama"
  base_model          = "qwen3:0.6b"
  model_api_base      = "http://qwen3-0-6b-ollama.ai:11434"
  mode                = "chat"
  tier                = "free"
  access_groups       = ["local-models"]

  input_cost_per_million_tokens  = 0
  output_cost_per_million_tokens = 0

  additional_litellm_params = {
    max_parallel_requests = "1"
  }
}

resource "litellm_model" "claude_opus_4_8" {
  model_name              = "claude-opus-4-8"
  custom_llm_provider     = "anthropic"
  base_model              = "claude-opus-4-8"
  model_api_base          = local.cliproxy_api_base
  litellm_credential_name = litellm_credential.cliproxy.credential_name
  mode                    = "chat"
  tier                    = "paid"
  access_groups           = ["frontier-models"]

  input_cost_per_million_tokens  = 15.0
  output_cost_per_million_tokens = 75.0

  additional_litellm_params = {
    max_parallel_requests = "1"
  }
}

resource "litellm_model" "claude_sonnet_4_6" {
  model_name              = "claude-sonnet-4-6"
  custom_llm_provider     = "anthropic"
  base_model              = "claude-sonnet-4-6"
  model_api_base          = local.cliproxy_api_base
  litellm_credential_name = litellm_credential.cliproxy.credential_name
  mode                    = "chat"
  tier                    = "paid"
  access_groups           = ["frontier-models"]

  input_cost_per_million_tokens  = 3.0
  output_cost_per_million_tokens = 15.0

  additional_litellm_params = {
    max_parallel_requests = "2"
  }
}
