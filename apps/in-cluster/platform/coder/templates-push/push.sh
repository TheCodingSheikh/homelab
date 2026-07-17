#!/bin/sh
set -eu

if coder login "$CODER_URL" \
  --first-user-username "$CODER_ADMIN_USERNAME" \
  --first-user-email "$CODER_ADMIN_EMAIL" \
  --first-user-password "$CODER_ADMIN_PASSWORD" \
  --first-user-trial=false >/dev/null 2>&1; then
  echo "bootstrapped first admin user: $CODER_ADMIN_USERNAME"
else
  CODER_SESSION_TOKEN="$(wget -qO- --header 'Content-Type: application/json' \
    --post-data "{\"email\":\"$CODER_ADMIN_EMAIL\",\"password\":\"$CODER_ADMIN_PASSWORD\"}" \
    "$CODER_URL/api/v2/users/login" | sed -n 's/.*"session_token":"\([^"]*\)".*/\1/p')"
  if [ -z "$CODER_SESSION_TOKEN" ]; then
    echo "login failed"
    exit 1
  fi
  export CODER_SESSION_TOKEN
fi

WORK=/tmp/templates
mkdir -p "$WORK"
for f in /templates-src/*.tf; do
  [ -e "$f" ] || continue
  tpl="$(basename "$f" .tf)"
  mkdir -p "$WORK/$tpl"
  cp "$f" "$WORK/$tpl/main.tf"
done

for dir in "$WORK"/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  version="v$(cat "$dir"/* | sha256sum | cut -c1-8)"

  versions="$(coder templates versions list "$name" 2>/dev/null || true)"

  if echo "$versions" | grep "^$version " | grep -q "Active"; then
    echo "$name: $version already active"
  elif echo "$versions" | grep -q "^$version "; then
    echo "$name: promoting existing version $version"
    coder templates versions promote --template "$name" --template-version "$version"
  else
    echo "$name: pushing $version"
    coder templates push "$name" --directory "$dir" --name "$version" --yes
  fi
done
