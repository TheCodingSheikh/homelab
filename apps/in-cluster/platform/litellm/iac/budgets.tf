resource "litellm_budget" "starter" {
  budget_id = "starter"

  max_budget      = 50.0
  soft_budget     = 40.0
  budget_duration = "30d"

  tpm_limit             = 200000
  rpm_limit             = 500
  max_parallel_requests = 10
}

resource "litellm_budget" "standard" {
  budget_id = "standard"

  max_budget      = 250.0
  soft_budget     = 200.0
  budget_duration = "30d"

  tpm_limit             = 800000
  rpm_limit             = 1500
  max_parallel_requests = 25
}
