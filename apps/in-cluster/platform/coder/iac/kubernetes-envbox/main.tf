terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

data "coder_parameter" "home_disk" {
  name        = "Disk Size"
  description = "How large should the disk storing the home directory be?"
  icon        = "/emojis/1f4be.png"
  type        = "number"
  default     = 10
  mutable     = true
  validation {
    min = 10
    max = 100
  }
}

variable "use_kubeconfig" {
  type        = bool
  default     = false
  description = <<-EOF
  Use host kubeconfig? (true/false)
  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.
  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
}

provider "coder" {}

variable "namespace" {
  type        = string
  description = "The namespace to create workspaces in (must exist prior to creating workspaces)"
  default     = "coder"
}

variable "create_tun" {
  type        = bool
  description = "Add a TUN device to the workspace."
  default     = false
}

variable "create_fuse" {
  type        = bool
  description = "Add a FUSE device to the workspace."
  default     = false
}

variable "max_cpus" {
  type        = string
  description = "Max number of CPUs the workspace may use (e.g. 2). Leave empty for no limit."
  default     = ""
}

variable "min_cpus" {
  type        = string
  description = "Minimum number of CPUs the workspace may use (e.g. .1). Leave empty for no request."
  default     = ""
}

variable "max_memory" {
  type        = string
  description = "Maximum amount of memory to allocate the workspace (in GB). Leave empty for no limit."
  default     = ""
}

variable "min_memory" {
  type        = string
  description = "Minimum amount of memory to allocate the workspace (in GB). Leave empty for no request."
  default     = ""
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  extensions_gallery = jsonencode({
    serviceUrl          = "https://marketplace.lab.com/api"
    itemUrl             = "https://marketplace.lab.com/item"
    resourceUrlTemplate = "https://marketplace.lab.com/files/{publisher}/{name}/{version}/{path}"
  })
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "arm64"

  env = {
    EXTENSIONS_GALLERY  = local.extensions_gallery
    NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca.crt"
  }

  startup_script = <<EOT
    #!/bin/bash
    # home folder can be empty, so copying default bash settings
    if [ ! -f ~/.profile ]; then
      cp /etc/skel/.profile $HOME
    fi
    if [ ! -f ~/.bashrc ]; then
      cp /etc/skel/.bashrc $HOME
    fi

    # Add any commands that should be executed at workspace startup (e.g install requirements, start a program, etc) here
  EOT
}

# code-server module in offline mode: it never downloads (no code-server.dev
# egress). The binary is seeded into the inner container at install_prefix by
# the init-container below and mounted in via CODER_MOUNTS.
module "code-server" {
  count          = data.coder_workspace.me.start_count
  source         = "https://s3.lab.com/public/terraform/modules/code-server-1.5.2.zip"
  agent_id       = coder_agent.main.id
  order          = 1
  offline        = true
  install_prefix = "/coder-tools/code-server"
}

resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}-home"
    namespace = var.namespace
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${data.coder_parameter.home_disk.value}Gi"
      }
    }
  }
}

resource "kubernetes_pod_v1" "main" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
    annotations = {
      "inject-certs" = "enabled"
    }
  }

  spec {
    restart_policy = "Never"

    # Seeds code-server from its image into a shared volume; the code-server
    # module (offline) then runs this copy instead of downloading. Mounted into
    # the inner container via CODER_MOUNTS.
    init_container {
      name    = "init-code-server"
      image   = "codercom/code-server:latest"
      command = ["sh", "-c", "cp -a /usr/lib/code-server /coder-tools/code-server"]
      security_context {
        run_as_user     = "0"
        run_as_non_root = false
      }
      volume_mount {
        mount_path = "/coder-tools"
        name       = "coder-tools"
      }
    }

    init_container {
      name  = "init-ca-certificates"
      image = "codercom/enterprise-base:ubuntu"
      command = ["sh", "-c", join(" && ", [
        "cp /etc/ssl/certs/ca.crt /usr/local/share/ca-certificates/lab.crt",
        "update-ca-certificates",
        "cp -a /etc/ssl/certs/. /certs/",
      ])]
      security_context {
        run_as_user     = "0"
        run_as_non_root = false
      }
      volume_mount {
        mount_path = "/certs"
        name       = "ssl-certs"
      }
    }

    container {
      name = "dev"
      # We highly recommend pinning this to a specific release of envbox, as the latest tag may change.
      image             = "ghcr.io/coder/envbox:latest"
      image_pull_policy = "Always"
      command           = ["/envbox", "docker"]

      security_context {
        privileged = true
      }

      dynamic "resources" {
        for_each = var.min_cpus != "" || var.max_cpus != "" || var.min_memory != "" || var.max_memory != "" ? [1] : []
        content {
          requests = merge(
            var.min_cpus != "" ? { "cpu" = var.min_cpus } : {},
            var.min_memory != "" ? { "memory" = "${var.min_memory}G" } : {},
          )
          limits = merge(
            var.max_cpus != "" ? { "cpu" = var.max_cpus } : {},
            var.max_memory != "" ? { "memory" = "${var.max_memory}G" } : {},
          )
        }
      }

      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }

      env {
        name  = "CODER_AGENT_URL"
        value = data.coder_workspace.me.access_url
      }

      env {
        # kyverno-injected lab CA; envbox installs it into the inner container
        # trust store and uses it for control-plane/registry connections
        name  = "CODER_EXTRA_CERTS_PATH"
        value = "/etc/ssl/certs/"
      }

      env {
        name  = "CODER_INNER_IMAGE"
        value = "index.docker.io/codercom/enterprise-base:ubuntu-20240812"
      }

      env {
        name  = "CODER_INNER_USERNAME"
        value = "coder"
      }

      env {
        name  = "CODER_BOOTSTRAP_SCRIPT"
        value = coder_agent.main.init_script
      }

      env {
        name  = "CODER_MOUNTS"
        value = "/home/coder:/home/coder,/coder-tools:/coder-tools"
      }

      env {
        name  = "CODER_ADD_FUSE"
        value = var.create_fuse
      }

      env {
        name  = "CODER_INNER_HOSTNAME"
        value = data.coder_workspace.me.name
      }

      env {
        name  = "CODER_ADD_TUN"
        value = var.create_tun
      }

      env {
        name = "CODER_CPUS"
        value_from {
          resource_field_ref {
            resource = "limits.cpu"
          }
        }
      }

      env {
        name = "CODER_MEMORY"
        value_from {
          resource_field_ref {
            resource = "limits.memory"
          }
        }
      }

      volume_mount {
        mount_path = "/home/coder"
        name       = "home"
        read_only  = false
        sub_path   = "home"
      }

      volume_mount {
        mount_path = "/var/lib/coder/docker"
        name       = "home"
        sub_path   = "cache/docker"
      }

      volume_mount {
        mount_path = "/var/lib/coder/containers"
        name       = "home"
        sub_path   = "cache/containers"
      }

      volume_mount {
        mount_path = "/var/lib/sysbox"
        name       = "sysbox"
      }

      volume_mount {
        mount_path = "/var/lib/containers"
        name       = "home"
        sub_path   = "envbox/containers"
      }

      volume_mount {
        mount_path = "/var/lib/docker"
        name       = "home"
        sub_path   = "envbox/docker"
      }

      volume_mount {
        mount_path = "/usr/src"
        name       = "usr-src"
      }

      volume_mount {
        mount_path = "/lib/modules"
        name       = "lib-modules"
      }

      volume_mount {
        mount_path = "/coder-tools"
        name       = "coder-tools"
      }

      volume_mount {
        mount_path = "/etc/ssl/certs"
        name       = "ssl-certs"
        read_only  = true
      }

    }

    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim_v1.home.metadata.0.name
        read_only  = false
      }
    }

    volume {
      name = "sysbox"
      empty_dir {}
    }

    volume {
      name = "coder-tools"
      empty_dir {}
    }

    volume {
      name = "ssl-certs"
      empty_dir {}
    }

    volume {
      name = "usr-src"
      host_path {
        path = "/usr/src"
        type = ""
      }
    }

    volume {
      name = "lib-modules"
      host_path {
        path = "/lib/modules"
        type = ""
      }
    }
  }
}