#!/bin/sh
# Registers artifacts dropped on the fileserver PVC into terralist.
#   providers: /srv/providers/<namespace>/terraform-provider-<name>_<ver>_<os>_<arch>.zip
#   modules:   /srv/modules/<namespace>/<name>/<system>/<version>.tgz
# Providers are self-signed here (terraform requires signed SHA256SUMS).
# Idempotent: versions already in terralist are skipped.
set -eu

: "${TERRALIST_API:?}"; : "${MASTER_API_KEY:?}"; : "${FILESERVER:?}"
SRV=/srv
mkdir -p "$SRV/providers" "$SRV/modules" 2>/dev/null || true

export GNUPGHOME=/tmp/gnupg; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
cat > /tmp/kp <<EOF
%no-protection
Key-Type: RSA
Key-Length: 3072
Name-Real: Terralist Airgapped Signer
Name-Email: terralist@lab.com
Expire-Date: 0
%commit
EOF
gpg --batch --gen-key /tmp/kp >/dev/null 2>&1
KEY_ID=$(gpg --list-keys --with-colons | awk -F: '/^pub:/{print $5; exit}')
ASCII_ARMOR=$(gpg --armor --export "$KEY_ID")

api() { curl -ksS -H "X-API-Key: $MASTER_API_KEY" -H "Content-Type: application/json" "$@"; }
ensure_authority() {
  ns=$1
  aid=$(api -X POST "$TERRALIST_API/v1/api/authorities/" -d "{\"name\":\"$ns\",\"public\":true}" | jq -r '.id // empty')
  [ -z "$aid" ] && aid=$(api "$TERRALIST_API/v1/api/authorities/" | jq -r ".[]?|select(.name==\"$ns\")|.id" | head -1)
  api -X POST "$TERRALIST_API/v1/api/authorities/$aid/keys" \
    -d "$(jq -n --arg k "$KEY_ID" --arg a "$ASCII_ARMOR" '{key_id:$k,ascii_armor:$a,trust_signature:""}')" >/dev/null 2>&1 || true
  echo "$aid"
}

echo "== providers =="
for nsdir in "$SRV"/providers/*/; do
  [ -d "$nsdir" ] || continue
  ns=$(basename "$nsdir")
  for nv in $(ls "$nsdir" 2>/dev/null | sed -n 's/^terraform-provider-\(.*\)_\([0-9][^_]*\)_[a-z0-9]*_[a-z0-9]*\.zip$/\1@\2/p' | sort -u); do
    name=${nv%@*}; ver=${nv#*@}
    existing=$(curl -ksS "$TERRALIST_API/v1/providers/$ns/$name/versions" | jq -r ".versions[]?.version" 2>/dev/null || true)
    if echo "$existing" | grep -qx "$ver"; then echo "  $ns/$name $ver exists"; continue; fi

    sums="terraform-provider-${name}_${ver}_SHA256SUMS"; : > "$nsdir$sums"; platforms='[]'
    for z in "$nsdir"terraform-provider-${name}_${ver}_*.zip; do
      [ -e "$z" ] || continue
      zf=$(basename "$z")
      oa=$(echo "$zf" | sed -n "s/^terraform-provider-${name}_${ver}_\([a-z0-9]*\)_\([a-z0-9]*\)\.zip$/\1 \2/p")
      os=$(echo "$oa" | awk '{print $1}'); arch=$(echo "$oa" | awk '{print $2}')
      sha=$(sha256sum "$z" | awk '{print $1}')
      printf '%s  %s\n' "$sha" "$zf" >> "$nsdir$sums"
      platforms=$(echo "$platforms" | jq -c --arg o "$os" --arg a "$arch" \
        --arg d "$FILESERVER/providers/$ns/$zf" --arg s "$sha" '.+[{os:$o,arch:$a,download_url:$d,shasum:$s}]')
    done
    gpg --batch --yes --detach-sign --output "$nsdir${sums}.sig" "$nsdir$sums"
    aid=$(ensure_authority "$ns")
    api -X POST "$TERRALIST_API/v1/api/providers/$ns/$name/$ver/upload" \
      -d "$(jq -n --arg u "$FILESERVER/providers/$ns/$sums" --arg g "$FILESERVER/providers/$ns/${sums}.sig" \
          --argjson pl "$platforms" '{shasums:{url:$u,signature_url:$g},protocols:["5.0","6.0"],platforms:$pl}')" \
      && echo "  provider $ns/$name $ver OK"
  done
done

echo "== modules =="
find "$SRV/modules" -name '*.tgz' 2>/dev/null | while read -r tgz; do
  rel=${tgz#"$SRV"/modules/}
  ns=$(echo "$rel" | cut -d/ -f1); name=$(echo "$rel" | cut -d/ -f2); system=$(echo "$rel" | cut -d/ -f3)
  ver=$(basename "$tgz" .tgz)
  [ -n "$ns" ] && [ -n "$name" ] && [ -n "$system" ] || { echo "  skip $rel (need ns/name/system/version.tgz)"; continue; }
  existing=$(curl -ksS "$TERRALIST_API/v1/modules/$ns/$name/$system/versions" | jq -r ".modules[0].versions[]?.version" 2>/dev/null || true)
  if echo "$existing" | grep -qx "$ver"; then echo "  $ns/$name/$system $ver exists"; continue; fi
  ensure_authority "$ns" >/dev/null
  api -X POST "$TERRALIST_API/v1/api/modules/$ns/$name/$system/$ver/upload" \
    -d "$(jq -n --arg u "$FILESERVER/modules/$rel" '{download_url:$u}')" && echo "  module $ns/$name/$system $ver OK"
done
echo DONE
