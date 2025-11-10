#!/usr/bin/env bash
set -euo pipefail

# === Config ===
CHAIN="${CHAIN:-31337}"                              # anvil por defecto
ROOT="${ROOT:-$(pwd)}"                               # repo root
RPC="${ETH_RPC_URL:-}"                               # si está, validamos con cast

USDC_SCRIPT="${USDC_SCRIPT:-DeployUSDC.s.sol}"
KGLD_SCRIPT="${KGLD_SCRIPT:-DeployKGLD.s.sol}"
FEED_SCRIPT="${FEED_SCRIPT:-DeployMockV3.s.sol}"

OUT_ENV="${OUT_ENV:-addresses.env}"
OUT_EXPORTS="${OUT_EXPORTS:-addresses.exports}"

# === Helpers ===
pick_json() {
  local script="$1"
  local dir="$ROOT/broadcast/$script/$CHAIN"
  # último run-*.json por mtime
  ls -t "$dir"/run-*.json 2>/dev/null | head -1
}

addr_from_json() {
  # Busca el primer contractAddress que sigue a contractName == $2
  local json="$1" name="$2"
  awk -v name="$name" '
    $0 ~ "\"contractName\"" && $0 ~ "\""name"\"" { inblk=1; next }
    inblk && $0 ~ "\"contractAddress\"" {
      match($0, /"contractAddress":[ ]*"([^"]+)"/, m)
      if (m[1]!="") { print m[1]; exit 0 }
    }
  ' "$json"
}

print_and_set() {
  local key="$1" val="$2"
  printf "%-6s: %s\n" "$key" "$val"
  echo "${key}=${val}" >> "$OUT_ENV"
  echo "export ${key}=${val}" >> "$OUT_EXPORTS"
}

erc20_meta() {
  local addr="$1"
  echo "-- $addr metadata --"
  ETH_RPC_URL="$RPC" cast call "$addr" "name()(string)"        || true
  ETH_RPC_URL="$RPC" cast call "$addr" "symbol()(string)"      || true
  ETH_RPC_URL="$RPC" cast call "$addr" "decimals()(uint8)"     || true
  ETH_RPC_URL="$RPC" cast call "$addr" "totalSupply()(uint256)"|| true
  echo
}

validate_code() {
  local label="$1" addr="$2"
  [[ -z "$RPC" ]] && return 0
  local code
  code=$(ETH_RPC_URL="$RPC" cast code "$addr" 2>/dev/null || echo "ERR")
  if [[ "$code" == "0x" ]]; then
    echo "WARN: $label en $addr no tiene bytecode en $RPC"
  elif [[ "$code" == "ERR" ]]; then
    echo "WARN: no se pudo consultar $label ($addr) con cast"
  else
    echo "OK: $label tiene bytecode (len ${#code})"
  fi
}

# === Inicio ===
: > "$OUT_ENV"
: > "$OUT_EXPORTS"

echo "== Buscando run-*.json (CHAIN=$CHAIN) =="

JSON_USDC=$(pick_json "$USDC_SCRIPT" || true)
JSON_KGLD=$(pick_json "$KGLD_SCRIPT" || true)
JSON_FEED=$(pick_json "$FEED_SCRIPT" || true)

[[ -z "${JSON_USDC:-}" ]] && echo "No encontré JSON de $USDC_SCRIPT" || echo "USDC JSON:  $JSON_USDC"
[[ -z "${JSON_KGLD:-}" ]] && echo "No encontré JSON de $KGLD_SCRIPT" || echo "KGLD JSON:  $JSON_KGLD"
[[ -z "${JSON_FEED:-}" ]] && echo "No encontré JSON de $FEED_SCRIPT" || echo "FEED JSON:  $JSON_FEED"
echo

USDC_ADDR=""
KGLD_ADDR=""
FEED_ADDR=""

[[ -n "${JSON_USDC:-}" ]] && USDC_ADDR=$(addr_from_json "$JSON_USDC" "MockUSDC" || true)
[[ -n "${JSON_KGLD:-}" ]] && KGLD_ADDR=$(addr_from_json "$JSON_KGLD" "KipuGLD" || true)
[[ -n "${JSON_FEED:-}" ]] && FEED_ADDR=$(addr_from_json "$JSON_FEED" "MockV3Aggregator" || true)

echo "== Addresses detectadas =="
[[ -n "$USDC_ADDR" ]] && print_and_set USDC "$USDC_ADDR"     || echo "USDC : (no hallado)"
[[ -n "$KGLD_ADDR" ]] && print_and_set KGLD "$KGLD_ADDR"     || echo "KGLD : (no hallado)"
[[ -n "$FEED_ADDR" ]] && print_and_set FEED "$FEED_ADDR"     || echo "FEED : (no hallado)"
echo
echo "Guardadas en:"
echo "  - $OUT_ENV"
echo "  - $OUT_EXPORTS"
echo

# === Validación opcional ===
if [[ -n "$RPC" ]]; then
  echo "== Validando en RPC: $RPC =="
  [[ -n "$USDC_ADDR" ]] && validate_code "USDC" "$USDC_ADDR"
  [[ -n "$KGLD_ADDR" ]] && validate_code "KGLD" "$KGLD_ADDR"
  [[ -n "$FEED_ADDR" ]] && validate_code "FEED" "$FEED_ADDR"
  echo

  [[ -n "$USDC_ADDR" ]] && erc20_meta "$USDC_ADDR"
  [[ -n "$KGLD_ADDR" ]] && erc20_meta "$KGLD_ADDR"
fi

echo "Listo."
