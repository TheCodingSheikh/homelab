locals {
  cliproxy_api_base = "http://cliproxy.ai:8317"
}

resource "litellm_credential" "cliproxy" {
  credential_name = "cliproxy"

  credential_values = {
    api_key = var.cliproxy_api_key
  }

  credential_info = {
    provider    = "anthropic"
    description = "cli-proxy-api in the ai namespace"
  }
}
