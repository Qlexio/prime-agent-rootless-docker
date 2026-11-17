#!/usr/bin/env bash
# prime-setup: add an OpenAI-compatible provider to Prime Agent (Pi-based)
#
# Both `bash -n prime-setup.sh` and `shellcheck prime-setup.sh` ran well.
# Tested against, everything passed as expected:
# [X] External API provider -> detects openai-responses
# [X] A llama.cpp server -> detects openai-responses
# [X] Missing `/v1` in provider url
# [X] A wrong key (401)
# [X] A dead host (000)

set -euo pipefail

CFG_DIR="${PRIME_CFG_DIR:-${HOME}/.prime/agent}"
MODELS="${CFG_DIR}/models.json"
BUILTINS="/opt/prime-defaults/builtin-providers.txt"
SCHEMA="https://pi.dev/schemas/models.schema.json"

warn() { printf '\033[33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# Refuse to write config for the wrong user (e.g. docker exec -u root)
OWNER_HOME="$(cd "${CFG_DIR%/.prime/agent}" 2>/dev/null && pwd || true)"
if [[ "$(id -u)" -eq 0 ]] || { [[ -n "$OWNER_HOME" ]] && [[ ! -O "$OWNER_HOME" ]]; }; then
  die "Run as the agent user: 'docker exec -it <container> prime-setup' (without -u root)"
fi

[[ -t 0 ]] || die "Interactive terminal required: 'docker exec -it <container> prime-setup'"
mkdir -p "$CFG_DIR"

# ---------- prompt helpers ----------
ask() {          # ask <var> <prompt> [default]
  local __a
  if [[ -n "${3-}" ]]; then
    read -rp "$2 [$3]: " __a;
    __a="${__a:-$3}"
  else
    read -rp "$2: " __a;
  fi
  printf -v "$1" '%s' "$__a"
}

ask_req() {      # non-empty answer
  while :; do
    ask "$@";
    [[ -n "${!1}" ]] && return;
    warn "A value is required.";
  done
}

yesno() {        # yesno <prompt> <Y|N>
  local a;
  read -rp "$1 [$([[ $2 == Y ]] && echo Y/n || echo y/N)]: " a
  a="${a:-$2}";
  [[ "$a" =~ ^[Yy] ]]
}

ask_int() {      # positive integer
  while :; do
    ask "$@";
    [[ "${!1}" =~ ^[1-9][0-9]*$ ]] && return;
    warn "Enter a positive integer.";
  done
}

ask_cost() {     # number >= 0
  while :; do
    ask "$@"; [[ "${!1}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && return;
    warn "Enter a number >= 0.";
  done
}

# ---------- 1. built-in or external ----------
if yesno "Use a built-in provider (OpenAI, Anthropic, OpenRouter...)?" Y; then
  cat <<'EOF'

Built-in providers need no models.json entry:
  1. start Prime Agent and run  /login   (stores credentials in auth.json)
  2. then pick a model with     /model   (or: prime-agent model)
EOF
  exit 0
fi

# ---------- 2. provider ----------
while :; do
  ask_req PID "Provider ID (a-z, 0-9, -)"
  if [[ ! "$PID" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    warn "Invalid ID.";
    continue;
  fi
  if [[ -f "$BUILTINS" ]] && grep -qxF "$PID" "$BUILTINS"; then
    warn "'$PID' is a built-in provider ID; using it would change that provider.";
    continue;
  fi
  if [[ -f "$MODELS" ]] && python3 - "$MODELS" "$PID" <<'PY' 2>/dev/null
import json,sys; sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1])).get("providers",{}) else 1)
PY
  then yesno "Provider '$PID' already exists. Replace it?" N || continue;
  fi
  break
done

ask PNAME "Display name" "$PID"

# ---------- 3. API key ----------
ENV_DEFAULT="$(tr 'a-z-' 'A-Z_' <<<"$PID")_API_KEY"
[[ "$ENV_DEFAULT" =~ ^[0-9] ]] && ENV_DEFAULT="P_${ENV_DEFAULT}"

echo "API key: 1) environment variable (recommended)  2) literal value"

ask KMODE "Choice" 1
if [[ "$KMODE" == 2 ]]; then
  while :; do
    read -rsp "API key (hidden): " KEY_VALUE;
    echo;
    [[ -n "$KEY_VALUE" ]] && break;
  done
  API_KEY_FIELD="$KEY_VALUE"
  ENVNAME=""
else
  while :; do
    ask ENVNAME "Variable name" "$ENV_DEFAULT"
    [[ "$ENVNAME" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && break;
    warn "Invalid variable name."
  done

  API_KEY_FIELD="\$${ENVNAME}"
  KEY_VALUE="${!ENVNAME-}"
  [[ -z "$KEY_VALUE" ]] && warn "\$${ENVNAME} is not set in this container; the check will run without a key."
fi

# ---------- 4. base URL + endpoint check ----------
ask_req URL "Base URL (e.g. http://192.168.1.10:8000)"
URL="${URL%/}"

if [[ "$URL" == */v1 ]]; then
  CANDIDATES=("$URL" "${URL%/v1}");
else
  CANDIDATES=("$URL/v1" "$URL");
fi

# ### Focus on one model; time to handle API connections specs ###
# probe() {
#   local h=();
#   [[ -n "$KEY_VALUE" ]] && h=(-H "Authorization: Bearer ${KEY_VALUE}" -H "Content-Type: application/json")
#   curl -fsS --max-time 8 "${h[@]}" "$1/models" 2>/dev/null
# }

# if [[ "$URL" == */v1 ]]; then
#   CANDIDATES=("$URL" "${URL%/v1}");
# else
#   CANDIDATES=("$URL/v1" "$URL");
# fi

# BASE="$URL"; BODY=""; VERIFIED=0
# for c in "${CANDIDATES[@]}"; do
#   if BODY="$(probe "$c")"; then
#     BASE="$c"; VERIFIED=1;
#     break;
#   fi
# done

# if (( VERIFIED )); then
#   echo "Endpoint OK: ${BASE}"
# else
#   warn "Endpoint unverified (unreachable, wrong URL or key). Writing '${BASE}' as entered.";
# fi
# ###

while :; do
  ask_req MID "Model ID, as the server expects it (e.g. gpt-4.1 or unsloth/Qwen3-8B-GGUF:Q4_K_M)"
  [[ -n "$MID" ]] && break
  echo "  A model ID is required."
done

echo "  Tip: increase it for local servers (first call loads the model), slow reasoning models or slow networks."
ask_int TIMEOUT "Request timeout in seconds" 30

# Prints the HTTP status; the body goes to $PROBE_BODY
probe() {  # probe <url> <json-body>
  local code
  code="$(
    { [[ -n "${KEY_VALUE:-}" ]] && printf 'header = "Authorization: Bearer %s"\n' "$KEY_VALUE"; } |
    curl -sS -K - --max-time "$TIMEOUT" -X POST -o "$PROBE_BODY" -w '%{http_code}' \
        -H "Content-Type: application/json" -d "$2" "$1" 2>/dev/null || true
  )"
  echo "${code:-000}"
}

# Prints the server's error message (if any) from $PROBE_BODY
server_msg() {
  python3 - "$PROBE_BODY" <<'PY' 2>/dev/null || true
import json, sys
raw = open(sys.argv[1], errors="replace").read()
try:
    d = json.loads(raw)
    e = d.get("error", d) if isinstance(d, dict) else d
    msg = e.get("message") if isinstance(e, dict) else e
    print(str(msg or raw)[:300])
except Exception:
    print(raw.strip()[:300])
PY
}

PROBE_BODY="$(mktemp)"; trap 'rm -f "$PROBE_BODY"' EXIT

# JSON bodies built by Python so any model ID is safely escaped
RESP_JSON="$(python3 -c 'import json,sys; print(json.dumps({"model": sys.argv[1], "input": "ping"}))' "$MID")"
CHAT_JSON="$(python3 -c 'import json,sys; print(json.dumps({"model": sys.argv[1], "messages": [{"role": "user", "content": "ping"}]}))' "$MID")"

BASE="$URL"
API="openai-responses"          # default, also used when nothing is verified
VERIFIED=0; LAST_CODE=000; LAST_URL=""

echo
echo "A test request (\"ping\") will be sent to check the URL, API key, model and API type."
echo "It uses a very small amount of tokens (typically well under \$0.01)."
if yesno "Send the test request?" Y; then
  for b in "${CANDIDATES[@]}"; do
    for api in openai-responses openai-completions; do
      if [[ "$api" == openai-responses ]]; then
        LAST_URL="${b}/responses";        body="$RESP_JSON"
      else
        LAST_URL="${b}/chat/completions"; body="$CHAT_JSON"
      fi
      LAST_CODE="$(probe "$LAST_URL" "$body")"
      if [[ "$LAST_CODE" == 2* ]]; then
        BASE="$b"; API="$api"; VERIFIED=1
        echo "OK: ${LAST_URL} -> ${API}"
        break 2
      fi
      [[ "$LAST_CODE" == 401 || "$LAST_CODE" == 403 ]] && break 2  # bad key: stop
      [[ "$LAST_CODE" == 000 ]] && break 2                         # unreachable / timeout: stop
    done
  done
else
  LAST_CODE=skip
fi

if (( ! VERIFIED )); then
  case "$LAST_CODE" in
    skip)    echo "Test skipped." ;;
    401|403) echo "Server answered ${LAST_CODE}: the API key looks wrong." ;;
    000)     echo "No answer within ${TIMEOUT}s (server down, wrong URL, network, or timeout too short)." ;;
    *)       echo "Server answered ${LAST_CODE} on ${LAST_URL}." ;;
  esac
  if [[ "$LAST_CODE" != skip && "$LAST_CODE" != 000 ]]; then
    msg="$(server_msg)"; [[ -n "$msg" ]] && echo "  Server says: ${msg}"
  fi
  echo "API type will default to: ${API}"
  yesno "Save the configuration anyway?" Y || die "Aborted."
fi

# ---------- 5. model ----------
# ### Focus on one model; time to handle API connections specs ###
# IDS=()

# if (( VERIFIED )); then
#   mapfile -t IDS < <(printf '%s' "$BODY" | python3 -c '
# import json,sys
# for m in json.load(sys.stdin).get("data",[]): print(m["id"])' 2>/dev/null || true)
# fi

# if (( ${#IDS[@]} )); then
#   echo "Models available:"
#   for i in "${!IDS[@]}"; do
#     printf '  %2d) %s\n' $((i+1)) "${IDS[i]}";
#   done
#   ask_req MSEL "Model (number or id)"
#   if [[ "$MSEL" =~ ^[0-9]+$ ]] && (( MSEL >= 1 && MSEL <= ${#IDS[@]} )); then
#     MID="${IDS[MSEL-1]}";
#   else MID="$MSEL";
#   fi
# else
#   ask_req MID "Model ID"
# fi
# ###

ask MNAME "Model display name" "$MID"

ask_int CTX "contextWindow" 128000
while :; do
  ask_int MAXT "maxTokens" 32768
  (( MAXT <= CTX )) && break;
  warn "maxTokens must be <= contextWindow ($CTX)."
done
if yesno "Reasoning model?" Y; then
  REASONING=1;
else
  REASONING=0;
fi

# ---------- 6. costs ----------
C_IN=0;
C_OUT=0;
C_CR=0;
C_CW=0

if yesno "Track usage costs?" N; then
  echo "Prices in USD per 1M tokens (0 allowed):"
  ask_cost C_IN  "  Input"       0
  ask_cost C_OUT "  Output"      0
  ask_cost C_CR  "  Cache read"  0
  ask_cost C_CW  "  Cache write" 0
fi

# ---------- 7. summary ----------
cat <<EOF

Provider : ${PID} (${PNAME})
Base URL : ${BASE} $( (( VERIFIED )) && echo "[verified]" || echo "[UNVERIFIED]")
API      : ${API} $( (( VERIFIED )) && echo "[detected]" || echo "[default]")
API key  : $( [[ -n "$ENVNAME" ]] && echo "\$${ENVNAME}" || echo "literal (hidden)")
Model    : ${MID} (${MNAME})  ctx=${CTX} max=${MAXT} reasoning=$( ((REASONING)) && echo yes || echo no)
Costs    : in=${C_IN} out=${C_OUT} cacheRead=${C_CR} cacheWrite=${C_CW}
EOF
yesno "Write ${MODELS}?" Y || { echo "Aborted, nothing written."; exit 0; }

# ---------- 8. write ----------
[[ -f "$MODELS" ]] && cp -p "$MODELS" "${MODELS}.bak" && echo "Backup: ${MODELS}.bak"

TMP="$(mktemp "${CFG_DIR}/.models.XXXXXX")"

MODELS="$MODELS" TMP="$TMP" SCHEMA="$SCHEMA" PID="$PID" PNAME="$PNAME" BASE="$BASE" API="$API" \
APIKEY="$API_KEY_FIELD" MID="$MID" MNAME="$MNAME" CTX="$CTX" MAXT="$MAXT" REASONING="$REASONING" \
C_IN="$C_IN" C_OUT="$C_OUT" C_CR="$C_CR" C_CW="$C_CW" python3 <<'PY'
import json, os, sys
e = os.environ
num = lambda s: int(float(s)) if float(s).is_integer() else float(s)
try:
    data = json.load(open(e["MODELS"]))
    if not isinstance(data, dict):
        raise ValueError
except FileNotFoundError:
    data = {}
except ValueError:
    print("[warn] existing models.json is invalid JSON; starting fresh (see .bak)", file=sys.stderr)
    data = {}
provs = data.get("providers") or {}
ph = provs.get("my-provider")
if ph and ph.get("baseUrl") == "https://api.example.com/v1":   # seeded placeholder
    provs.pop("my-provider")
provs[e["PID"]] = {
    "name": e["PNAME"],
    "baseUrl": e["BASE"],
    "api": e["API"],
    "apiKey": f'!printenv {e["APIKEY"][1:]}',
    "authHeader": True,
    "compat": {
        "supportsDeveloperRole": True,
        "supportsReasoningEffort": True,
        "supportsUsageInStreaming": True,
    },
    "models": [{
        "id": e["MID"],
        "name": e["MNAME"],
        "reasoning": e["REASONING"] == "1",
        "input": ["text"],
        "contextWindow": int(e["CTX"]),
        "maxTokens": int(e["MAXT"]),
        "cost": {"input": num(e["C_IN"]), "output": num(e["C_OUT"]),
                 "cacheRead": num(e["C_CR"]), "cacheWrite": num(e["C_CW"])},
    }],
}
out = {"$schema": e["SCHEMA"]}
out.update({k: v for k, v in data.items() if k not in ("$schema", "providers")})
out["providers"] = provs
with open(e["TMP"], "w") as f:
    json.dump(out, f, indent=2, ensure_ascii=False); f.write("\n")
PY
chmod 600 "$TMP" && mv "$TMP" "$MODELS"
echo "Written ${MODELS} (600)"

[[ -n "$ENVNAME" && -z "${!ENVNAME-}" ]] && cat <<EOF

Reminder: \$${ENVNAME} must exist in the container's environment.
Recreate the container with:  -e ${ENVNAME}=...   (or an --env-file)
EOF
echo "Next: in Prime Agent, run /model (or: prime-agent model) and pick ${PID}/${MID}."