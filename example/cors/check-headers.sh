#!/usr/bin/env bash
#
# Dumps the actual CORS headers each demo function returns.
#
# The browser deliberately hides these from JavaScript, so index.html can only
# report allowed vs blocked. Use this to see the bytes on the wire.
#
# Usage:
#   ./check-headers.sh <base-url> [trusted-origin]
#
#   ./check-headers.sh http://127.0.0.1:5001/demo-test/us-central1
#   ./check-headers.sh https://us-central1-my-project.cloudfunctions.net

set -uo pipefail

BASE="${1:-}"
TRUSTED="${2:-http://localhost:8000}"
UNTRUSTED="https://evil.example"

if [ -z "$BASE" ]; then
  sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

BASE="${BASE%/}"

if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  BOLD=''; DIM=''; RESET=''
fi

FUNCTIONS=(
  corsoff
  corsoptout
  corsreflectany
  corswildcard
  corssingleorigin
  corsallowlist
  corspattern
  corsthrows401
  corsthrows500
  corscallable
)

# Prints the CORS-relevant response headers, or "(none)" if there are none.
cors_headers() {
  grep -iE '^(access-control-|vary:)' \
    | sed 's/\r$//' \
    | sed "s/^/      /" \
    | grep . || echo "      ${DIM}(no CORS headers)${RESET}"
}

probe_simple() {
  local fn="$1" origin="$2" method="$3"
  local out status
  out=$(curl -sS -o /dev/null -D - -X "$method" \
        -H "Origin: $origin" \
        ${4:+-H "$4"} \
        ${5:+--data "$5"} \
        "$BASE/$fn" 2>&1)
  status=$(printf '%s' "$out" | awk 'toupper($1) ~ /^HTTP/ {print $2}' | tail -1)
  echo "    ${DIM}$method from $origin${RESET} -> ${status:-no response}"
  printf '%s\n' "$out" | cors_headers
}

probe_preflight() {
  local fn="$1" origin="$2"
  local out status
  out=$(curl -sS -o /dev/null -D - -X OPTIONS \
        -H "Origin: $origin" \
        -H "Access-Control-Request-Method: POST" \
        -H "Access-Control-Request-Headers: authorization,content-type" \
        "$BASE/$fn" 2>&1)
  status=$(printf '%s' "$out" | awk 'toupper($1) ~ /^HTTP/ {print $2}' | tail -1)
  echo "    ${DIM}preflight from $origin${RESET} -> ${status:-no response}"
  printf '%s\n' "$out" | cors_headers
}

echo
echo "${BOLD}Base:${RESET}      $BASE"
echo "${BOLD}Trusted:${RESET}   $TRUSTED"
echo "${BOLD}Untrusted:${RESET} $UNTRUSTED"
echo
echo "${DIM}Look for: Authorization echoed in Access-Control-Allow-Headers on"
echo "preflights; Vary present whenever the origin is reflected; CORS headers"
echo "still present on the 401 and 500.${RESET}"

for fn in "${FUNCTIONS[@]}"; do
  echo
  echo "${BOLD}$fn${RESET}"
  if [ "$fn" = "corscallable" ]; then
    probe_preflight "$fn" "$TRUSTED"
    probe_simple "$fn" "$TRUSTED" POST "Content-Type: application/json" '{"data":{}}'
  else
    probe_preflight "$fn" "$TRUSTED"
    probe_simple "$fn" "$TRUSTED" GET
    probe_simple "$fn" "$UNTRUSTED" GET
  fi
done

echo
