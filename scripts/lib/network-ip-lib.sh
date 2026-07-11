#!/usr/bin/env bash
# Public IP probe helpers for network popups / status scripts.

# Print a public IPv4/IPv6 address to stdout, or return non-zero.
# Tries several HTTPS endpoints (curl, then wget).
get_public_ip() {
  local ip="" url
  local -a urls=(
    "https://api64.ipify.org?format=text"
    "https://ifconfig.me/ip"
    "https://icanhazip.com"
    "https://checkip.amazonaws.com"
  )

  if command -v curl >/dev/null 2>&1; then
    for url in "${urls[@]}"; do
      ip=$(curl -fsS --connect-timeout 2 --max-time 4 "$url" 2>/dev/null \
        | tr -d '\r' \
        | awk 'NR==1 {gsub(/[[:space:]]/, ""); print; exit}')
      [ -n "$ip" ] && {
        printf '%s' "$ip"
        return 0
      }
    done
  fi

  if command -v wget >/dev/null 2>&1; then
    for url in "${urls[@]}"; do
      ip=$(wget -qO- --timeout=4 "$url" 2>/dev/null \
        | tr -d '\r' \
        | awk 'NR==1 {gsub(/[[:space:]]/, ""); print; exit}')
      [ -n "$ip" ] && {
        printf '%s' "$ip"
        return 0
      }
    done
  fi

  return 1
}
