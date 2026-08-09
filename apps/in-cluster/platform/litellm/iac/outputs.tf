# provider-terraform publishes these into litellm-tf-outputs, sensitive included.

output "service_account_keys" {
  value = {
    openwebui   = litellm_key.openwebui.key
    holmesgpt   = litellm_key.holmesgpt.key
    open-design = litellm_key.open_design.key
  }
  sensitive = true
}

output "team_ids" {
  value = {
    platform = litellm_team.platform.id
    general  = litellm_team.general.id
  }
}

output "organization_id" {
  value = litellm_organization.lab.organization_id
}
