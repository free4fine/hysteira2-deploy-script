#!/usr/bin/env bash
set -uo pipefail
PROJECT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$PROJECT/hysteria-maintain"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
CONFIG=$fixture/config.yaml
STATE=$fixture/state
BINARY=$fixture/hysteria
mkdir "$STATE"
printf 'ports.example.com\n' > "$STATE/domain"
cat > "$CONFIG" <<'CONFIG'
listen: :8443
masquerade:
  listenHTTPS: :9443
CONFIG
cat > "$BINARY" <<'BIN'
#!/usr/bin/env bash
printf 'Version: v2.13.0\n'
BIN
chmod +x "$BINARY"
fail() { echo "FAIL: $*" >&2; exit 1; }
require_root() { return 0; }
busy=''
ss() {
  printf '%s\n' "$*" >> "$fixture/ss-calls"
  case "$*" in
    *-lnup*|*-lntp*) echo 'users:(("hysteria",pid=123,fd=3))' ;;
    *-lnt*) [[ $busy == tcp ]] && echo LISTEN ;;
    *-lnu*) [[ $busy == udp ]] && echo UNCONN ;;
  esac
  return 0
}
systemctl() {
  case "$1" in
    is-active) echo inactive; return 3 ;;
    is-enabled) return 0 ;;
    show) echo 123 ;;
  esac
}
curl() {
  printf '%s\n' "$*" >> "$fixture/curl-calls"
  case "$*" in *api.ipify.org*) echo 192.0.2.1;; *api6.ipify.org*) echo 2001:db8::1;; *) echo 200;; esac
}
timeout() { shift; "$@"; }
getent() { return 0; }
openssl() { printf '%s\n' "$*" >> "$fixture/openssl-calls"; return 1; }
journalctl() { return 0; }
load_settings
check_ports_available || fail '空闲自定义端口'
busy=tcp
if check_ports_available >/dev/null; then fail 'TCP 占用未被阻止'; fi
busy=udp
if check_ports_available >/dev/null; then fail 'UDP 占用未被阻止'; fi
busy=''
echo 'PASS: 根据向导参数检查 TCP/UDP 端口占用'
output=$(check_status); result=$?
[[ $result == 1 ]] || fail '模拟停止服务应返回异常'
[[ $output == *'UDP 8443'* && $output == *'TCP 9443'* && $output == *'https://ports.example.com:9443/'* ]] || fail '状态页端口'
grep -q 'sport = :8443' "$fixture/ss-calls" && grep -q 'sport = :9443' "$fixture/ss-calls" || fail '监听检查端口'
grep -q 'ports.example.com:9443:127.0.0.1 https://ports.example.com:9443/' "$fixture/curl-calls" || fail '网站检查端口'
grep -q '127.0.0.1:9443' "$fixture/openssl-calls" || fail '证书检查端口'
echo 'PASS: 状态页、网站和证书检查使用自定义端口'
printf 'listen: :443\nmasquerade:\n  listenHTTPS: :443\n' > "$CONFIG"
load_settings
[[ $PROXY_PORT == 443 && $WEB_PORT == 443 ]] || fail '旧版 443 配置兼容'
echo 'PASS: 兼容旧版默认 443 配置'
