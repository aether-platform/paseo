#!/usr/bin/env bash
# Aether fork 版 @getpaseo/* を Index の npm 面（Verdaccio, :4873）へ依存順に発行する。
#
# 失敗時は即座に止まる（D-12）: 途中のパッケージが失敗したら、それより後ろは一つも出さない。
# 以前の手作業版は server が HTTP 413 で落ちた後も cli を出してしまい、
# 「cli は載っているが依存先の server が無くて install が解決しない」組が Index に残った。
#
# 使い方:
#   NPM_TOKEN=<発行用トークン> scripts/aether/publish-to-index-verdaccio.sh <tgz のディレクトリ> [版]
#   版を省略すると packages/server/package.json の version を使う。
#   DRY_RUN=1 で検査だけ行い、npm publish は呼ばない。
#
# 環境変数:
#   NPM_TOKEN         発行用トークン（必須。DRY_RUN=1 のときは不要）。値は表示しない
#   INDEX_NPM_REGISTRY 既定 http://index.fleet.internal:4873/
#   NPM_DIST_TAG      既定 aether（latest は上流の版のまま触らない）
#   MAX_BODY_MB       Verdaccio の max_body_size（既定 32。2026-11-12 の J-4 で 10mb → 32mb）
#
# 受信上限の注記: npm publish は tgz を base64 にして JSON に入れるため、要求本文は
# tgz の約 4/3 倍になる。server は Web UI を同梱していて 0.15.4-aether.1 で tgz 17.0MB
# （本文 約 23MB）。上限を超えるものが一つでもあれば、何も出さずに止める。
set -euo pipefail

TGZ_DIR=${1:?usage: $0 <tgz-dir> [version]}
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VERSION=${2:-$(node -p "require('$REPO_ROOT/packages/server/package.json').version")}
REGISTRY=${INDEX_NPM_REGISTRY:-http://index.fleet.internal:4873/}
DIST_TAG=${NPM_DIST_TAG:-aether}
MAX_BODY_MB=${MAX_BODY_MB:-32}
DRY_RUN=${DRY_RUN:-0}

# 依存順（cli は server・client・protocol に完全一致で依存する）
PACKAGES=(highlight relay protocol client plugin server cli)

case "$DIST_TAG" in latest) echo "ERROR: dist-tag latest は使わない（上流の版を上書きしない）" >&2; exit 2 ;; esac
if [ "$DRY_RUN" != 1 ] && [ -z "${NPM_TOKEN:-}" ]; then
  echo "ERROR: NPM_TOKEN が空" >&2; exit 2
fi

# --- 1. 発行前の検査（ここで一つでも落ちたら何も出さない） ---
max_body=$((MAX_BODY_MB * 1024 * 1024))
declare -A TGZ
for p in "${PACKAGES[@]}"; do
  f="$TGZ_DIR/getpaseo-$p-$VERSION.tgz"
  [ -f "$f" ] || { echo "ERROR: $f が無い" >&2; exit 1; }
  name=$(tar -xOzf "$f" package/package.json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.name+"@"+j.version)})')
  [ "$name" = "@getpaseo/$p@$VERSION" ] || { echo "ERROR: $f の中身が $name（期待 @getpaseo/$p@$VERSION）" >&2; exit 1; }
  size=$(stat -c %s "$f")
  body=$(( size * 4 / 3 + 65536 ))
  if [ "$body" -gt "$max_body" ]; then
    echo "ERROR: $p は要求本文 約$((body/1024/1024))MB で上限 ${MAX_BODY_MB}MB を超える（tgz $((size/1024/1024))MB）。基盤に max_body_size の引き上げを依頼する" >&2
    exit 1
  fi
  echo "check ok: @getpaseo/$p@$VERSION tgz=${size}B body~$((body/1024/1024))MB"
  TGZ[$p]=$f
done
if [ -f "$TGZ_DIR/SHA512SUMS.txt" ]; then
  (cd "$TGZ_DIR" && sha512sum -c --quiet SHA512SUMS.txt)
  echo "check ok: SHA512SUMS.txt"
else
  echo "WARN: $TGZ_DIR/SHA512SUMS.txt が無いので sha512 の照合を飛ばす" >&2
fi

# --- 2. 一時 npmrc（mode 600、終了時に必ず消す） ---
NPMRC=$(mktemp)
chmod 600 "$NPMRC"
trap 'rm -f "$NPMRC"' EXIT
host=${REGISTRY#*://}
{
  echo "registry=$REGISTRY"
  echo "@getpaseo:registry=$REGISTRY"
  [ "$DRY_RUN" = 1 ] || echo "//${host%/}/:_authToken=\${NPM_TOKEN}"
} > "$NPMRC"
npmx() { npm --userconfig "$NPMRC" --registry "$REGISTRY" "$@"; }

# --- 3. 依存順に発行。失敗したらその場で止める ---
published=()
for i in "${!PACKAGES[@]}"; do
  p=${PACKAGES[$i]}
  spec="@getpaseo/$p@$VERSION"
  if npmx view "$spec" version >/dev/null 2>&1; then
    echo "skip: $spec は登録済み"
    continue
  fi
  if [ "$DRY_RUN" = 1 ]; then
    echo "dry-run: npm publish ${TGZ[$p]} --tag $DIST_TAG"
    continue
  fi
  if ! npmx publish "${TGZ[$p]}" --tag "$DIST_TAG" --access public; then
    echo "ERROR: $spec の発行に失敗。後続（${PACKAGES[*]:$((i+1))}）は出していない" >&2
    echo "今回出したもの: ${published[*]:-なし}" >&2
    exit 1
  fi
  published+=("$spec")
done

# --- 4. 資格なしの形で引けるか・dist-tag を確認 ---
[ "$DRY_RUN" = 1 ] && { echo "dry-run 終了"; exit 0; }
CHECKRC=$(mktemp); trap 'rm -f "$NPMRC" "$CHECKRC"' EXIT
printf 'registry=%s\n@getpaseo:registry=%s\n' "$REGISTRY" "$REGISTRY" > "$CHECKRC"
for p in "${PACKAGES[@]}"; do
  got=$(npm --userconfig "$CHECKRC" view "@getpaseo/$p@$VERSION" version)
  tag=$(npm --userconfig "$CHECKRC" view "@getpaseo/$p" "dist-tags.$DIST_TAG")
  [ "$got" = "$VERSION" ] && [ "$tag" = "$VERSION" ] || { echo "ERROR: @getpaseo/$p: version=$got dist-tags.$DIST_TAG=$tag" >&2; exit 1; }
  echo "verify ok: @getpaseo/$p@$VERSION ($DIST_TAG)"
done
echo "done: 今回出したもの ${published[*]:-なし}"
