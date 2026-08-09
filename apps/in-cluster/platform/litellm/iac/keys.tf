# Values are published to litellm-tf-outputs via outputs.tf; README.md covers
# the cutover from the keys these apps currently hardcode.

resource "litellm_key" "openwebui" {
  service_account_id = "openwebui"
  team_id            = litellm_team.platform.id

  models = ["frontier-models", "local-models"]
  # info_routes so the UI can read /models for its picker.
  allowed_routes = ["llm_api_routes", "info_routes"]

  budget_id = litellm_budget.standard.budget_id
  rpm_limit = 600
  tpm_limit = 400000

  tags = [litellm_tag.openwebui.name]

  depends_on = [
    litellm_model.qwen3_0_6b,
    litellm_model.claude_opus_4_8,
    litellm_model.claude_sonnet_4_6,
  ]
}

# apps/in-cluster/ai/holmesgpt names claude-opus-4-7 and claude-opus-4-6 in its
# modelList; neither exists here, so those calls 400 until one side is fixed.
resource "litellm_key" "holmesgpt" {
  service_account_id = "holmesgpt"
  team_id            = litellm_team.platform.id

  models         = ["claude-sonnet-4-6", "qwen3:0.6b"]
  allowed_routes = ["llm_api_routes"]

  budget_id = litellm_budget.starter.budget_id
  rpm_limit = 120
  tpm_limit = 100000

  tags = [litellm_tag.holmesgpt.name]

  depends_on = [
    litellm_model.qwen3_0_6b,
    litellm_model.claude_sonnet_4_6,
  ]
}

resource "litellm_key" "open_design" {
  service_account_id = "open-design"
  team_id            = litellm_team.platform.id

  models         = ["claude-opus-4-8", "claude-sonnet-4-6"]
  allowed_routes = ["llm_api_routes"]

  budget_id = litellm_budget.starter.budget_id
  rpm_limit = 120
  tpm_limit = 200000

  tags = [litellm_tag.open_design.name]

  depends_on = [
    litellm_model.claude_opus_4_8,
    litellm_model.claude_sonnet_4_6,
  ]
}
