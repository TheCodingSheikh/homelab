# Coder — airgapped operations

Workspaces have **no runtime internet dependency**:

- **code-server** is seeded into each workspace by an init container (from the
  `codercom/code-server` image) — never downloaded from `code-server.dev`.
- **Editor extensions** come from the in-cluster **code-marketplace**
  (`marketplace.lab.com`) — the workspace `EXTENSIONS_GALLERY` points there.
- **Terraform providers** come from a **network mirror** served by the
  in-cluster S3 (`s3.lab.com/public/terraform/`). No GPG signing, no registry API.
- **Terraform modules** come from the same S3 as plain **tarballs**
  (`s3.lab.com/public/terraform/modules/`). No registry, no egress.

The cluster is **arm64**.

---

## Terraform providers (network mirror — no signing)

Coder's server-side terraform is pointed at a network mirror via
`chart/terraformrc.yaml` (`TF_CLI_CONFIG_FILE`):

```hcl
provider_installation {
  network_mirror { url = "https://s3.lab.com/public/terraform/" }
}
```

This intercepts every `registry.terraform.io` provider, so templates keep plain
sources (`coder/coder`, `hashicorp/kubernetes`) — no per-template rewrite. The
mirror protocol needs no GPG signatures; integrity is the plain hashes that
`terraform providers mirror` generates. HTTPS is zero-setup: the coder pod
already trusts the lab CA (kyverno `inject-certs`).

The mirror is object storage — the SeaweedFS S3 (`storage/seaweedfs`), exposed
at `s3.lab.com` and served from the anonymous-read `public` bucket.

### Populate the mirror — build once, upload once

Nothing in the cluster reaches the internet. You generate the mirror on a
connected machine and push it to S3. `scripts/terraform/mirror.sh` does both:
it reads `providers.txt` + `modules.txt`, runs `terraform providers mirror` and
packages the modules into `out/`, then offers to `mc mirror` the tree to S3.

```sh
cd scripts/terraform
# edit providers.txt / modules.txt to taste, then:
./mirror.sh
# when prompted:
#   S3 endpoint : https://s3.lab.com
#   Bucket name : public/terraform      <- note the prefix
#   Access key / Secret key : the seaweedfs admin creds
```

The `public/terraform` prefix is what makes the objects line up with the
`network_mirror` URL above (`.../public/terraform/registry.terraform.io/...`).
That's it — coder picks providers up on the next build.

---

## Terraform modules (plain tarballs — no registry)

Modules don't need a registry or signing either — terraform fetches a tarball by
URL (go-getter). They're served from the same `public/terraform/modules/` on S3.

`scripts/terraform/mirror.sh` already packages every entry in `modules.txt`
(both `registry.coder.com/...` sources, resolved via `terraform get`, and
`github.com/...` sources) into `out/modules/<name>-<ver>.zip` and uploads them
alongside the providers. To add one, append it to `modules.txt` and re-run.

Reference it from a template by URL — no `version` (that's registry-only):

```hcl
module "mymod" {
  source = "https://s3.lab.com/public/terraform/modules/mymod-1.2.3.zip"
}
```

The `kubernetes-envbox` template pulls `code-server` (v1.5.2) this way. For a
subdirectory inside the archive, append `//subdir`. HTTPS is zero-setup — the
coder pod trusts the lab CA.

Alternatively, vendor a module straight into the template directory and use a
relative `source = "./mymod"` (requires pushing the module files alongside the
template).

### Airgap note — modules that download at runtime

Fetching a module from S3 only removes the *build-time* registry dependency. A
module's script may still reach the internet when the workspace boots:

- **`code-server`** runs in `offline = true` mode. The binary is seeded into the
  workspace by an init-container (copied from the `codercom/code-server` image,
  same trick as the `kubernetes` template) and handed to the inner envbox
  container via `CODER_MOUNTS` — so the module launches it instead of curling
  `code-server.dev`. Zero runtime egress.
- **`jetbrains`** was removed. It calls `data.services.jetbrains.com` at *plan*
  time (breaking the airgapped push) and pulls IDE backends from
  `download.jetbrains.com` at runtime. Supporting it needs an internal JetBrains
  mirror (`releases_base_link` / `download_base_link` overrides) — not set up.

Both templates are otherwise self-contained: providers via the S3 mirror,
extensions via `marketplace.lab.com`, images via the cluster registry.

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
