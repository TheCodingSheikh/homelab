#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(pwd)/out"
PLATFORMS="linux_amd64"
mkdir -p "$OUT"

# ---------- providers ----------
if [[ -f providers.txt ]]; then
  work=$(mktemp -d)
  count=0
  {
    echo 'terraform {'
    echo '  required_providers {'
    while read -r source version || [[ -n "${source:-}" ]]; do
      source=$(tr -d '\r' <<< "$source"); version=$(tr -d '\r' <<< "${version:-}")
      [[ -z "$source" || "$source" == \#* ]] && continue
      name="${source##*/}"
      echo "    $name = { source = \"$source\", version = \"$version\" }"
      count=$((count+1))
    done < providers.txt
    echo '  }'
    echo '}'
  } > "$work/versions.tf"

  echo ">> $count provider(s) in manifest:"
  cat "$work/versions.tf"

  args=()
  for p in $PLATFORMS; do args+=(-platform="$p"); done
  (cd "$work" && terraform providers mirror "${args[@]}" "$OUT")
  rm -rf "$work"
  echo ">> providers done"
else
  echo "!! providers.txt not found in $(pwd), skipping"
fi

# ---------- modules ----------
if [[ -f modules.txt ]]; then
  mkdir -p "$OUT/modules"
  while read -r src ver || [[ -n "${src:-}" ]]; do
    src=$(tr -d '\r' <<< "$src"); ver=$(tr -d '\r' <<< "${ver:-}")
    [[ -z "$src" || "$src" == \#* ]] && continue

    if [[ "$src" == */*/*/* ]]; then
      IFS='/' read -r _host _ns name _system <<< "$src"
      file="$OUT/modules/${name}-${ver}.zip"
      [[ -f "$file" ]] && { echo ">> skip $file (exists)"; continue; }

      echo ">> resolving $src $ver"
      work=$(mktemp -d)
      printf 'module "m" {\n  source  = "%s"\n  version = "%s"\n}\n' "$src" "$ver" > "$work/main.tf"
      (cd "$work" && terraform get < /dev/null)
      dir=$(python3 -c "import json;print(json.load(open('$work/.terraform/modules/modules.json'))['Modules'][-1]['Dir'])" 2>/dev/null \
            || echo ".terraform/modules/m")
      (cd "$work/$dir" && zip -qr "$file" . -x '.git/*')
      rm -rf "$work"
      echo ">> module ok: $file"
    else
      name="${src##*/}"; name="${name#terraform-}"
      file="$OUT/modules/${name}-${ver#v}.zip"
      [[ -f "$file" ]] && { echo ">> skip $file (exists)"; continue; }
      echo ">> downloading github.com/$src @ $ver"
      curl -sfL "https://github.com/$src/archive/refs/tags/$ver.zip" -o "$file" < /dev/null
    fi
  done < modules.txt
  echo ">> modules done"
else
  echo "!! modules.txt not found in $(pwd), skipping"
fi

# ---------- upload ----------
read -rp "Upload to S3? [y/N] " yn
if [[ "$yn" == [yY]* ]]; then
  read -rp  "S3 endpoint (e.g. https://s3.lab.com): " endpoint
  read -rp  "Bucket name: " bucket
  read -rp  "Access key: " access
  read -rsp "Secret key: " secret; echo

  mc alias set tfmirror "$endpoint" "$access" "$secret" >/dev/null
  mc mirror --overwrite "$OUT" "tfmirror/$bucket"
  mc alias remove tfmirror >/dev/null
  echo ">> uploaded to $bucket"
fi