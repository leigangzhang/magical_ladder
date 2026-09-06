#!/usr/bin/env bash

# ============================================================================
# show-peers.sh - 用设备名显示每个 peer 的状态与累计流量
# 用法：./scripts/show-peers.sh [接口名]   默认 wg0
# ============================================================================

IFACE="${1:-wg0}"

MAP=""
for f in "$(dirname "$0")/../peers.map" "/etc/wireguard/peers.map" "peers.map"; do
  [ -f "$f" ] && MAP="$f" && break
done

declare -A NAME IP
if [ -n "$MAP" ]; then
  while IFS=$'\t' read -r name ip pk; do
    case "$name" in ''|'#'*) continue ;; esac
    NAME["$pk"]="$name"
    IP["$pk"]="$ip"
  done < "$MAP"
fi

hb() { awk -v b="$1" 'BEGIN{ if(b>=1073741824) printf "%.2f GiB", b/1073741824; else if(b>=1048576) printf "%.1f MiB", b/1048576; else if(b>=1024) printf "%.1f KiB", b/1024; else printf "%d B", b }'; }

printf '%-12s %-15s %-24s %10s %12s %12s\n' DEVICE IP ENDPOINT HANDSHAKE '上行(累计)' '下行(累计)'

wg show "$IFACE" dump 2>/dev/null | while IFS=$'\t' read -r -a F; do
  [ "${#F[@]}" -ge 8 ] || continue
  pub="${F[0]}"; ep="${F[2]:-}"; aip="${F[3]:-}"; hs="${F[4]:-}"; rx="${F[5]:-0}"; tx="${F[6]:-0}"
  name="${NAME[$pub]:-${pub:0:8}}"
  ip="${IP[$pub]:-${aip%%,*}}"
  [ -z "$ip" ] && ip="-"
  if [ -z "$hs" ] || [ "$hs" = "0" ]; then hst="从未"; else hst="${hs}s"; fi
  [ -z "$ep" ] && ep="-"
  printf '%-12s %-15s %-24s %10s %12s %12s\n' "$name" "$ip" "$ep" "$hst" "$(hb "$rx")" "$(hb "$tx")"
done
