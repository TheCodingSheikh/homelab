# terraform{}, provider{}, the backend and litellm_api_key are declared in
# ../providerconfig/providerconfig.yaml, which provider-terraform writes into
# the workspace. Repeating them here is a duplicate-block error at init.

variable "cliproxy_api_key" {
  description = "API key accepted by cli-proxy-api in the ai namespace."
  type        = string
  sensitive   = true
  default     = "secret"
}
