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
STATE=$TEST_ROOT/state
BINARY=$TEST_ROOT/usr/local/bin/hysteria
UNIT_DIR=$TEST_ROOT/units
SITE=$TEST_ROOT/www/far-and-field
SERVICE=hysteria-server.service
require_root() { return 0; }
wait_for_https() { return 0; }
check_status() { echo '模拟服务状态检查完成'; }
systemctl() {
  case "$1" in
    is-active) return 0 ;;
    show) echo 123 ;;
    *) return 0 ;;
  esac
}
ss() { echo 'users:(("hysteria",pid=123,fd=3))'; }
curl() {
  local output=''
  while (( $# )); do
    if [[ $1 == -o ]]; then output=$2; shift; fi
    shift
  done
  cp "$TEST_ROOT/official-fixture" "$output"
}
mkdir -p "$(dirname "$BINARY")" "$CONFIG_DIR" "$STATE" "$UNIT_DIR" "$SITE"
touch "$STATE/owned"
printf '<html>Far and Field</html>\n' > "$SITE/index.html"
printf '%s\n' 'upgrade.example.com' > "$STATE/domain"
printf '%s\n' 'test-password' > "$STATE/password"
printf 'listen: :8443\nacme:\n  domains:\n    - upgrade.example.com\nmasquerade:\n  listenHTTPS: :9443\n' > "$CONFIG"
printf 'unit\n' > "$UNIT_DIR/hysteria-server.service"
printf 'template unit\n' > "$UNIT_DIR/hysteria-server@.service"
cat > "$BINARY" <<'BINARY'
#!/usr/bin/env bash
VERSION=v2.12.0
printf 'Version:\t%s\n' "$VERSION"
BINARY
chmod +x "$BINARY"
printf 'v2.13.0\n' > "$TEST_ROOT/latest"
cat > "$TEST_ROOT/official-fixture" <<'FIXTURE'
#!/usr/bin/env bash
set -e
if [[ ${1:-} == --check ]]; then
  printf 'Checking for installed version ... %s\n' "$("$TEST_ROOT/usr/local/bin/hysteria" version | awk '$1 == "Version:" {print $2}')"
  printf 'Checking for latest version ... %s\n' "$(cat "$TEST_ROOT/latest")"
  exit 0
fi
if [[ ${1:-} == --version ]]; then
  cat > "$TEST_ROOT/usr/local/bin/hysteria" <<BINARY
#!/usr/bin/env bash
VERSION=$2
printf 'Version:\\t%s\\n' "\$VERSION"
BINARY
  chmod +x "$TEST_ROOT/usr/local/bin/hysteria"
  if [[ -e $TEST_ROOT/fail-upgrade ]]; then exit 1; fi
  exit 0
fi
exit 2
FIXTURE
cp "$TEST_ROOT/official-fixture" "$STATE/install-official.sh"
config_before=$(sha256sum "$CONFIG" | awk '{print $1}')
password_before=$(sha256sum "$STATE/password" | awk '{print $1}')
upgrade_service <<< y > "$TEST_ROOT/upgrade-output" || fail '升级成功路径'
[[ $(installed_version) == v2.13.0 ]] || fail '目标版本'
[[ $(sha256sum "$CONFIG" | awk '{print $1}') == "$config_before" &&
   $(sha256sum "$STATE/password" | awk '{print $1}') == "$password_before" ]] || fail '配置和密码未保留'
[[ -n $(find "$STATE" -name 'upgrade-backup-*' -type d) ]] || fail '升级前备份'
pass '升级版本、备份和保留配置密码'

upgrade_service <<< n > "$TEST_ROOT/cancel-output" || fail '取消同版本重新安装'
[[ $(installed_version) == v2.13.0 ]] || fail '取消后版本变化'
pass '最新版本取消重新安装'

upgrade_service <<< y > "$TEST_ROOT/reinstall-output" || fail '同版本重新安装'
[[ $(installed_version) == v2.13.0 ]] || fail '同版本重新安装失败'
pass '最新版本同版本重新安装'

printf 'v2.14.0\n' > "$TEST_ROOT/latest"
touch "$TEST_ROOT/fail-upgrade"
if upgrade_service <<< y > "$TEST_ROOT/failure-output" 2>&1; then fail '失败升级被视为成功'; fi
[[ $("$BINARY" version | awk '$1 == "Version:" {print $2}') == v2.13.0 ]] || fail '失败后程序未回滚'
[[ $(sha256sum "$CONFIG" | awk '{print $1}') == "$config_before" &&
   $(sha256sum "$STATE/password" | awk '{print $1}') == "$password_before" ]] || fail '失败后配置密码未恢复'
pass '官方安装失败时回滚程序和配置'

rm "$TEST_ROOT/fail-upgrade"
printf 'failed\n' > "$TEST_ROOT/latest"
if upgrade_service > "$TEST_ROOT/check-failure-output" 2>&1; then fail '版本查询异常未被拒绝'; fi
[[ $("$BINARY" version | awk '$1 == "Version:" {print $2}') == v2.13.0 ]] || fail '查询异常修改了程序'
pass '版本查询失败不会修改服务'
echo '所有升级测试通过；未连接或更改真实服务器。'
