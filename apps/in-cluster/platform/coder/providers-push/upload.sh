#!/bin/sh
set -eu

: "${TERRALIST_API:?}"
: "${MASTER_API_KEY:?}"
PROVIDERS="${PROVIDERS:-coder/coder hashicorp/kubernetes}"
PLATFORMS="${PLATFORMS:-linux/amd64 linux/arm64}"
REGISTRY="${UPSTREAM_REGISTRY:-https://registry.terraform.io}"

WORK=/tmp/work
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

export GNUPGHOME="$WORK/.gnupg"
mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
cat > "$WORK/keyparams" <<EOF
%no-protection
Key-Type: RSA
Key-Length: 3072
Name-Real: Terralist Airgapped Signer
Name-Email: terralist@lab.com
Expire-Date: 0
%commit
EOF
gpg --batch --gen-key "$WORK/keyparams" >/dev/null 2>&1
KEY_ID=$(gpg --list-keys --with-colons | awk -F: '/^pub:/{print $5; exit}')
ASCII_ARMOR=$(gpg --armor --export "$KEY_ID")

POD_IP=$(hostname -i | awk '{print $1}')
FILE_BASE="http://$POD_IP:8080"
( cd "$WORK" && python3 -m http.server 8080 >/dev/null 2>&1 ) &
sleep 1

api() { curl -ksS -H "X-API-Key: $MASTER_API_KEY" -H "Content-Type: application/json" "$@"; }

for p in $PROVIDERS; do
  ns=${p%%/*}; name=${p#*/}
  echo "== $ns/$name =="
  ver=$(curl -fsSL "$REGISTRY/v1/providers/$ns/$name" | jq -r .version)

  existing=$(curl -ksS "$TERRALIST_API/v1/providers/$ns/$name/versions" | jq -r ".versions[]?.version" 2>/dev/null || true)
  if echo "$existing" | grep -qx "$ver"; then
    echo "  $ver already published, skipping"
    continue
  fi

  sums="terraform-provider-${name}_${ver}_SHA256SUMS"
  : > "$WORK/$sums"
  platforms_json="[]"
  protos='["5.0"]'
  for plat in $PLATFORMS; do
    os=${plat%%/*}; arch=${plat#*/}
    meta=$(curl -fsSL "$REGISTRY/v1/providers/$ns/$name/$ver/download/$os/$arch")
    protos=$(echo "$meta" | jq -c '.protocols // ["5.0"]')
    zip="terraform-provider-${name}_${ver}_${os}_${arch}.zip"
    curl -fsSL "$(echo "$meta" | jq -r .download_url)" -o "$WORK/$zip"
    shasum=$(sha256sum "$WORK/$zip" | awk '{print $1}')
    printf '%s  %s\n' "$shasum" "$zip" >> "$WORK/$sums"
    platforms_json=$(echo "$platforms_json" | jq -c \
      --arg os "$os" --arg arch "$arch" --arg dl "$FILE_BASE/$zip" --arg sha "$shasum" \
      '. + [{os:$os,arch:$arch,download_url:$dl,shasum:$sha}]')
  done
  gpg --batch --yes --detach-sign --output "$WORK/${sums}.sig" "$WORK/$sums"

  aid=$(api -X POST "$TERRALIST_API/v1/api/authorities/" \
        -d "{\"name\":\"$ns\",\"policy_url\":\"\",\"public\":true}" | jq -r '.id // empty')
  if [ -z "$aid" ]; then
    aid=$(api "$TERRALIST_API/v1/api/authorities/" | jq -r ".[]? | select(.name==\"$ns\") | .id" | head -1)
  fi
  api -X POST "$TERRALIST_API/v1/api/authorities/$aid/keys" \
    -d "$(jq -n --arg k "$KEY_ID" --arg a "$ASCII_ARMOR" '{key_id:$k, ascii_armor:$a, trust_signature:""}')" \
    >/dev/null 2>&1 || true

  body=$(jq -n --arg surl "$FILE_BASE/$sums" --arg sigurl "$FILE_BASE/${sums}.sig" \
    --argjson protos "$protos" --argjson platforms "$platforms_json" \
    '{shasums:{url:$surl,signature_url:$sigurl},protocols:$protos,platforms:$platforms}')
  echo "  uploading $ver ($PLATFORMS)"
  api -X POST "$TERRALIST_API/v1/api/providers/$ns/$name/$ver/upload" -d "$body" && echo "  OK"
done

echo "DONE"
