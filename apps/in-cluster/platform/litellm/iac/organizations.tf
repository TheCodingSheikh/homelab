resource "litellm_organization" "lab" {
  organization_alias = "lab"

  max_budget      = 1000.0
  budget_duration = "30d"
  tpm_limit       = 2000000
  rpm_limit       = 5000
}
