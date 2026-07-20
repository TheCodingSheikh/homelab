resource "coderd_template" "kubernetes" {
  name         = "kubernetes"
  display_name = "Kubernetes"
  description  = "Provision Kubernetes Deployments as Coder workspaces."
  versions = [{
    directory = "${path.module}/kubernetes"
    active    = true
  }]
}

resource "coderd_template" "kubernetes_envbox" {
  name         = "kubernetes-envbox"
  display_name = "Kubernetes (envbox)"
  description  = "Provision envbox pods as Coder workspaces."
  versions = [{
    directory = "${path.module}/kubernetes-envbox"
    active    = true
  }]
}
