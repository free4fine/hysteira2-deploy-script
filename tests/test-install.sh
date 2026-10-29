#!/usr/bin/env bash
set -uo pipefail
PROJECT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$PROJECT/hysteria-maintain"
TEST_ROOT=$(mktemp -d)
export TEST_ROOT
trap 'rm -rf -- "$TEST_ROOT"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
if ! command -v sha256sum >/dev/null; then sha256sum() { shasum -a 256 "$@"; }; fi
CONFIG_DIR=$TEST_ROOT/etc/hysteria
CONFIG=$CONFIG_DIR/config.yaml
SITE=$TEST_ROOT/www/far-and-field
STATE=$TEST_ROOT/state
BINARY=$TEST_ROOT/usr/local/bin/hysteria
UNIT_DIR=$TEST_ROOT/units
CLI_PATH=$TEST_ROOT/usr/local/bin/hysteria-maintain
BUNDLE=$TEST_ROOT/bundle
require_root() { return 0; }
ensure_dependencies() { return 0; }
check_status() { echo '模拟服务状态检查完成'; }
ss() { return 0; }
systemctl() { printf '%s\n' "$*" >> "$TEST_ROOT/service-calls"; }
openssl() { [[ $1 == rand ]] || return 1; printf '%048d\n' 1; }
curl() {
  local output=''
  while (( $# )); do
    if [[ $1 == -o ]]; then output=$2; shift; fi
    shift
  done
  cp "$TEST_ROOT/official-fixture" "$output"
}
cat > "$TEST_ROOT/official-fixture" <<'FIXTURE'
#!/usr/bin/env bash
set -e
if [[ ${1:-} == --remove ]]; then
  rm -f "$TEST_ROOT/usr/local/bin/hysteria" "$TEST_ROOT/units/hysteria-server.service" "$TEST_ROOT/units/hysteria-server@.service"
else
  mkdir -p "$TEST_ROOT/etc/hysteria" "$TEST_ROOT/usr/local/bin" "$TEST_ROOT/units"
  [[ -f $TEST_ROOT/etc/hysteria/config.yaml ]] || echo 'example config' > "$TEST_ROOT/etc/hysteria/config.yaml"
  touch "$TEST_ROOT/usr/local/bin/hysteria" "$TEST_ROOT/units/hysteria-server.service" "$TEST_ROOT/units/hysteria-server@.service"
fi
FIXTURE

valid_domain example.com && valid_domain xn--example-9d0b.net || fail '合法域名校验'
for bad in '-bad.com' 'bad-.com' 'bad..com' 'bad/com' 'bad.com;echo' '.bad.com' 'bad.com.' 'localhost' '*.com'; do
  if valid_domain "$bad"; then fail "接受了非法域名 $bad"; fi
done
pass '域名校验'
archive=$PROJECT/assets/far-and-field.zip
validate_website_archive "$archive" || fail '自带网站包'
pass '自带 ZIP 校验'
mkdir -p "$TEST_ROOT/corrupt"
cp "$archive" "$archive.sha256" "$TEST_ROOT/corrupt/"
printf 'corrupt' >> "$TEST_ROOT/corrupt/far-and-field.zip"
if validate_website_archive "$TEST_ROOT/corrupt/far-and-field.zip" >/dev/null 2>&1; then fail '损坏的 ZIP 未被拒绝'; fi
pass '损坏的 ZIP 被拒绝'
mkdir -p "$TEST_ROOT/unsafe/site"
printf '<html>test</html>' > "$TEST_ROOT/unsafe/site/index.html"
mkdir "$TEST_ROOT/unsafe/site/assets"
ln -s /etc/passwd "$TEST_ROOT/unsafe/site/link"
(cd "$TEST_ROOT/unsafe/site" && zip -qy -r ../far-and-field.zip .) || fail '构造符号链接测试包'
sha256sum "$TEST_ROOT/unsafe/far-and-field.zip" > "$TEST_ROOT/unsafe/far-and-field.zip.sha256"
if validate_website_archive "$TEST_ROOT/unsafe/far-and-field.zip" >/dev/null 2>&1; then fail '符号链接 ZIP 未被拒绝'; fi
pass '符号链接 ZIP 被拒绝'
rm "$TEST_ROOT/unsafe/site/link" "$TEST_ROOT/unsafe/far-and-field.zip"
echo 'outside' > "$TEST_ROOT/unsafe/outside"
(cd "$TEST_ROOT/unsafe/site" && zip -q -r ../far-and-field.zip . ../outside) || fail '构造路径穿越测试包'
sha256sum "$TEST_ROOT/unsafe/far-and-field.zip" > "$TEST_ROOT/unsafe/far-and-field.zip.sha256"
if validate_website_archive "$TEST_ROOT/unsafe/far-and-field.zip" >/dev/null 2>&1; then fail '路径穿越 ZIP 未被拒绝'; fi
pass '路径穿越 ZIP 被拒绝'

mkdir -p "$(dirname "$BINARY")"
touch "$BINARY"
if install_service <<< 'deploy.example.com' >/dev/null 2>&1; then fail '已有程序覆盖保护'; fi
[[ ! -e $STATE ]] || fail '冲突时创建了安装状态'
rm "$BINARY"
pass '已有安装冲突保护'
if install_service <<< 'invalid;domain.com' >/dev/null 2>&1; then fail '非法域名安装'; fi
[[ ! -e $STATE ]] || fail '非法域名创建了安装状态'
pass '非法域名不进入安装'

install_service <<< 'deploy.example.com' > "$TEST_ROOT/install-output" || fail '首次安装'
[[ -f $SITE/index.html && -f $SITE/assets/images/coast.jpg && -f $CLI_PATH && -f $BUNDLE/assets/far-and-field.zip ]] || fail '安装后的独立文件'
[[ $(cat "$STATE/domain") == deploy.example.com ]] || fail '保存域名'
grep -q 'deploy.example.com' "$CONFIG" || fail '配置域名'
grep -q 'listenHTTPS: :443' "$CONFIG" || fail '网站 443 配置'
cmp "$SITE/index.html" <(unzip -p "$archive" index.html) || fail '解压网站内容'
[[ $(find "$SITE" -type f | wc -l | tr -d ' ') == 21 ]] || fail '网站文件完整性'
[[ -r $STATE/password && -f $STATE/owned ]] || fail '管理状态'
password_before=$(cat "$STATE/password")
config_before=$(sha256sum "$CONFIG" | awk '{print $1}')
pass '首次安装自动部署完整网站与持久安装包'

if install_website "$archive" >/dev/null 2>&1; then fail '覆盖了现有网站'; fi
pass '网站目录覆盖保护'
install_service <<< n > /dev/null || fail '拒绝重新安装'
[[ $(sha256sum "$CONFIG" | awk '{print $1}') == "$config_before" ]] || fail '取消重装后配置改变'
pass '重复安装确认取消'
echo 'custom content' > "$SITE/custom.html"
install_service <<< y > /dev/null || fail '重新安装'
[[ $(cat "$STATE/password") == "$password_before" && $(sha256sum "$CONFIG" | awk '{print $1}') == "$config_before" && -f $SITE/custom.html ]] || fail '重装未保留现有资料'
[[ -n $(find "$STATE" -name 'backup-*' -type d) ]] || fail '未备份配置'
pass '重装保留密码配置网站并备份'
rm -f "$STATE/domain"
DOMAIN=wrong.example.com
load_domain
[[ $DOMAIN == deploy.example.com ]] || fail '旧部署域名兼容'
pass '兼容现有 JP1 域名读取'
remove_service <<< n > /dev/null || fail '取消删除'
[[ -f $SITE/index.html ]] || fail '取消删除后丢失网站'
remove_service <<< y > /dev/null || fail '删除'
[[ ! -e $SITE && ! -e $STATE && ! -e $CONFIG_DIR && -f $CLI_PATH && -f $BUNDLE/assets/far-and-field.zip ]] || fail '卸载范围'
pass '删除清理运行文件并保留重新安装资料'

# Simulate invoking the installed command after the original uploaded project is gone.
SCRIPT_DIR=$(dirname "$CLI_PATH")
DOMAIN=deploy.example.com
install_service <<< '' > /dev/null || fail '仅使用保留的包重新安装'
[[ -f $SITE/index.html && -f $STATE/password ]] || fail '重新安装后的网站'
pass '不依赖原项目目录或 /home/ubuntu/dist 即可再次安装'
echo '所有测试通过；未安装或更改真实系统服务。'
