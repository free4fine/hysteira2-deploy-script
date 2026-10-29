#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if (( $# != 1 )); then echo '用法：bash tools/package-website.sh /绝对路径/网站dist目录' >&2; exit 2; fi
source_dir=$(cd -- "$1" && pwd)
[[ -f $source_dir/index.html && -d $source_dir/assets ]] || { echo '网站目录缺少 index.html 或 assets/。' >&2; exit 1; }
if [[ -n $(find "$source_dir" -type l -print -quit) ]]; then echo '网站目录不能包含符号链接。' >&2; exit 1; fi
mkdir -p "$PROJECT_ROOT/assets"
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
archive=$stage/far-and-field.zip
(cd "$source_dir" && COPYFILE_DISABLE=1 zip -X -qr "$archive" . -x '*/.DS_Store' '.DS_Store' '__MACOSX/*')
unzip -tq "$archive" >/dev/null
if command -v sha256sum >/dev/null; then
  (cd "$stage" && sha256sum far-and-field.zip) > "$stage/far-and-field.zip.sha256"
else
  (cd "$stage" && shasum -a 256 far-and-field.zip) > "$stage/far-and-field.zip.sha256"
fi
cp "$archive" "$archive.sha256" "$PROJECT_ROOT/assets/"
printf '已生成：%s/assets/far-and-field.zip\n' "$PROJECT_ROOT"
