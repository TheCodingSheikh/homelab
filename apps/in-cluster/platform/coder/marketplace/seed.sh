#!/bin/sh
# Seed the marketplace with a small set of commonly-used extensions from Open
# VSX. Offline-safe: if the PVC already holds extensions we skip the network
# entirely, so pod restarts don't depend on external connectivity. In a fully
# airgapped site, swap the Open VSX URLs for .vsix files staged on internal
# storage — the `add` command is identical.
set -u

EXT_DIR=/extensions
mkdir -p "$EXT_DIR"

if [ -n "$(ls -A "$EXT_DIR" 2>/dev/null)" ]; then
  echo "Marketplace already seeded ($(ls -1 "$EXT_DIR" | wc -l) entries); skipping."
  exit 0
fi

# publisher.name identifiers (all present on Open VSX)
EXTENSIONS="redhat.vscode-yaml esbenp.prettier-vscode golang.go hashicorp.terraform ms-python.python"

for ext in $EXTENSIONS; do
  ns=$(echo "$ext" | cut -d. -f1)
  name=$(echo "$ext" | cut -d. -f2-)
  echo "==> resolving $ext"
  url=$(wget -qO- "https://open-vsx.org/api/$ns/$name/latest" 2>/dev/null \
    | tr ',' '\n' | grep -o '"download":"[^"]*"' | head -1 \
    | sed 's/"download":"//; s/"$//')
  if [ -z "$url" ]; then
    echo "    could not resolve download URL for $ext, skipping"
    continue
  fi
  echo "    adding $url"
  /opt/code-marketplace add "$url" --extensions-dir "$EXT_DIR" || echo "    add failed for $ext (continuing)"
done

echo "==> seed complete; contents of $EXT_DIR:"
ls -1 "$EXT_DIR" 2>/dev/null || true
