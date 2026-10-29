#!/usr/bin/env bash
set -uo pipefail
PROJECT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$PROJECT/hysteria-maintain"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
DOMAIN=ready.example.com
WEB_PORT=9443
active=1
mode=retry
systemctl() { (( active )); }
sleep() { SECONDS=$((SECONDS + $1)); }
curl() {
  printf '%s\n' "$*" >> "$fixture/curl-calls"
  if [[ $mode == retry && ! -f $fixture/attempted ]]; then
    touch "$fixture/attempted"
    printf '000'; return 60
  fi
  if [[ $mode == timeout ]]; then printf '503'; else printf '200'; fi
}
fail() { echo "FAIL: $*" >&2; exit 1; }
wait_for_https 10 > "$fixture/output" || fail '证书尚未就绪后重试'
[[ $(wc -l < "$fixture/curl-calls" | tr -d ' ') == 2 ]] || fail '没有重试证书校验失败'
grep -q -- '--noproxy \*' "$fixture/curl-calls" || fail '没有绕过环境代理'
grep -q 'ready.example.com:9443:127.0.0.1 https://ready.example.com:9443/' "$fixture/curl-calls" || fail '就绪检查没有使用配置端口和域名'
echo 'PASS: 首次证书未就绪时重试，成功后再进入状态检查'
mode=timeout
if wait_for_https 3 > "$fixture/output"; then fail 'HTTP 非 200 被误判就绪'; fi
grep -q '超时' "$fixture/output" || fail '没有超时提示'
echo 'PASS: HTTPS 持续失败时在期限内结束并提示查看日志'
active=0
if wait_for_https 10 > "$fixture/output"; then fail '停止服务被误判就绪'; fi
grep -q '服务尚未运行' "$fixture/output" || fail '没有服务异常提示'
echo 'PASS: 服务停止时及时报告异常'
