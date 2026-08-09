# user_id must be the Keycloak preferred_username — both the UI SSO flow and the
# JWT path resolve a caller to that claim, so anything else creates a second
# user on first login.

resource "litellm_user" "abdo" {
  user_id    = "abdo"
  user_email = "abdo@lab.com"
  user_alias = "Abdo"
  user_role  = "proxy_admin"

  teams = [
    litellm_team.platform.id,
    litellm_team.general.id,
  ]
  models = []

  max_budget      = 200.0
  budget_duration = "30d"

  auto_create_key = false
}

# The membership, not the `teams` list, carries the per-team role and budget.
resource "litellm_team_member" "abdo_platform" {
  team_id    = litellm_team.platform.id
  user_id    = litellm_user.abdo.user_id
  user_email = litellm_user.abdo.user_email
  role       = "admin"

  max_budget_in_team = 200.0
}
