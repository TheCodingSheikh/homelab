# Coder — airgapped operations

Workspaces have **no runtime internet dependency**:

- **code-server** is seeded into each workspace by an init container (from the
  `codercom/code-server` image) — never downloaded from `code-server.dev`.
- **Editor extensions** come from the in-cluster **code-marketplace**
  (`marketplace.lab.com`) — the workspace `EXTENSIONS_GALLERY` points there.
- **Terraform providers** come from a **network mirror** served by terralist
  (`terralist.lab.com/files/mirror/`). No GPG signing, no registry API.

The cluster is **arm64**.

---

## Terraform providers (network mirror — no signing)

Coder's server-side terraform is pointed at a network mirror via
`chart/terraformrc.yaml` (`TF_CLI_CONFIG_FILE`):

```hcl
provider_installation {
  network_mirror { url = "https://terralist.lab.com/files/mirror/" }
}
```

This intercepts every `registry.terraform.io` provider, so templates keep plain
sources (`coder/coder`, `hashicorp/kubernetes`) — no per-template rewrite. The
mirror protocol needs no GPG signatures; integrity is the plain hashes that
`terraform providers mirror` generates. HTTPS is zero-setup: the coder pod
already trusts the lab CA (kyverno `inject-certs`).

The mirror is served by an **nginx sidecar** in the terralist pod from the
`terralist-files` PVC, exposed at `terralist.lab.com/files`.

### Populate / refresh the mirror

**Option A — in-cluster (uses the cluster's egress).** The `terralist-mirror-gen`
Job runs `terraform providers mirror` into the PVC. Trigger it by **syncing the
terralist app in Argo** (it's a Sync hook), or:

```sh
kubectl -n terralist create job --from=... # or just re-sync terralist in Argo
```

To change which providers/versions are mirrored, edit
`terralist/mirror/job.yaml` (the `required_providers` block) and re-sync.

**Option B — fully offline.** On a connected machine:

```sh
mkdir mirror && cd mirror
cat > providers.tf <<'EOF'
terraform {
  required_providers {
    coder      = { source = "coder/coder" }
    kubernetes = { source = "hashicorp/kubernetes" }
  }
}
EOF
terraform providers mirror -platform=linux_arm64 -platform=linux_amd64 ./out
```

Then drop `./out/*` into the mirror on the fileserver PVC:

```sh
POD=$(kubectl -n terralist get pod -l app.kubernetes.io/name=terralist -o jsonpath='{.items[0].metadata.name}')
kubectl -n terralist cp ./out "$POD:/srv/mirror" -c fileserver
```

Browse what's mirrored at `https://terralist.lab.com/files/`.

---

## code-marketplace (VS Code extension gallery)

Runs in the `coder` namespace, served at `https://marketplace.lab.com`.
Extensions live on the `code-marketplace` PVC (`/extensions`). It starts **empty**.

### How workspaces consume it

The template sets `EXTENSIONS_GALLERY` on the agent, so inside code-server the
Extensions panel and `code-server --install-extension <id>` both hit
`marketplace.lab.com`. Nothing is auto-installed.

### Add extensions

```sh
POD=$(kubectl -n coder get pod -l app.kubernetes.io/name=code-marketplace -o name)

# from Open VSX (needs egress at add-time):
kubectl -n coder exec "$POD" -- /opt/code-marketplace add \
  https://open-vsx.org/api/redhat/vscode-yaml/latest/file/redhat.vscode-yaml-latest.vsix \
  --extensions-dir /extensions

# from a local .vsix:
kubectl -n coder cp ./my-ext.vsix coder/${POD##*/}:/tmp/my-ext.vsix
kubectl -n coder exec "$POD" -- /opt/code-marketplace add /tmp/my-ext.vsix --extensions-dir /extensions
```

No restart needed — the server reads `/extensions` per request.

### List / remove

```sh
kubectl -n coder exec "$POD" -- ls /extensions
kubectl -n coder exec "$POD" -- /opt/code-marketplace remove <publisher>.<name> --extensions-dir /extensions
```
