# Global; the platform team overrides these in teams.tf. `general` fires only
# after router_settings.num_retries is exhausted.

resource "litellm_fallback" "opus_general" {
  model           = litellm_model.claude_opus_4_8.model_name
  fallback_models = [litellm_model.claude_sonnet_4_6.model_name]
  fallback_type   = "general"
}

resource "litellm_fallback" "sonnet_general" {
  model           = litellm_model.claude_sonnet_4_6.model_name
  fallback_models = [litellm_model.qwen3_0_6b.model_name]
  fallback_type   = "general"
}

resource "litellm_fallback" "local_context_window" {
  model           = litellm_model.qwen3_0_6b.model_name
  fallback_models = [litellm_model.claude_sonnet_4_6.model_name]
  fallback_type   = "context_window"
}
