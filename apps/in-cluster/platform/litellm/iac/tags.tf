# Cost attribution across teams. reject_clientside_metadata_tags in the Helm
# values stops a caller charging someone else's line.

resource "litellm_tag" "openwebui" {
  name        = "openwebui"
  description = "apps/in-cluster/ai/openwebui"

  max_budget      = 200.0
  soft_budget     = 160.0
  budget_duration = "30d"
  rpm_limit       = 600
}

resource "litellm_tag" "holmesgpt" {
  name        = "holmesgpt"
  description = "apps/in-cluster/ai/holmesgpt"

  max_budget      = 50.0
  soft_budget     = 40.0
  budget_duration = "30d"
  rpm_limit       = 120
}

resource "litellm_tag" "open_design" {
  name        = "open-design"
  description = "apps/in-cluster/ai/open-design"

  max_budget      = 100.0
  soft_budget     = 80.0
  budget_duration = "30d"
  rpm_limit       = 120
}
