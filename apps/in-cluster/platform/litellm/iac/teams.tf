# `models` holds access group names, not model names.

resource "litellm_team" "platform" {
  team_alias      = "platform"
  organization_id = litellm_organization.lab.organization_id

  models = ["frontier-models", "local-models"]

  max_budget      = 500.0
  budget_duration = "30d"
  tpm_limit       = 1000000
  rpm_limit       = 2000

  team_member_budget    = 100.0
  team_member_rpm_limit = 500
  team_member_tpm_limit = 200000

  model_aliases = {
    opus   = "claude-opus-4-8"
    sonnet = "claude-sonnet-4-6"
    local  = "qwen3:0.6b"
  }

  # Resolves key > team > global, so this overrides fallbacks.tf for this team.
  router_settings = {
    fallbacks = [
      {
        model           = "claude-opus-4-8"
        fallback_models = ["claude-sonnet-4-6"]
      },
    ]
    context_window_fallbacks = []
  }
}

resource "litellm_team" "general" {
  team_alias      = "general"
  organization_id = litellm_organization.lab.organization_id

  models = ["local-models"]

  max_budget      = 50.0
  budget_duration = "30d"
  tpm_limit       = 200000
  rpm_limit       = 500

  team_member_budget    = 10.0
  team_member_rpm_limit = 100
  team_member_tpm_limit = 50000
}
