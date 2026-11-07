#!/usr/bin/env bash
set -euo pipefail

MARKER="${HOME}/.prime-agent-installed"

log() { printf '[entrypoint] %s\n' "$*"; }

if [[ ! -f "${MARKER}" ]]; then
    log "First launch: installing Prime Agent into ${HOME} ..."

    if [[ -z "${PRIME_INSTALL_CMD:-}" ]]; then
        log "ERROR: PRIME_INSTALL_CMD is empty."
        log "Set it at build time (--build-arg) or run time (-e PRIME_INSTALL_CMD=...)."
        exit 1
    fi

    # Standard install, exactly as the README describes it
    bash -c "${PRIME_INSTALL_CMD}"

    date -Iseconds > "${MARKER}"
    log "Install done."
else
    log "Prime Agent already installed ($(cat "${MARKER}"))."
fi

# --- Seed default config files (never overwrite) ---
PRIME_CFG="${PRIME_CFG_DIR:-${HOME}/.prime/agent}"
mkdir -p "${PRIME_CFG}"

seed() {  # seed <file> <mode>
  local src="/opt/prime-defaults/$1" dst="${PRIME_CFG}/$1"
  if [ ! -e "${dst}" ] && [ -f "${src}" ]; then
    install -m "$2" "${src}" "${dst}"
    echo "[entrypoint] Seeded ${dst} — edit it before use."
  fi
}

seed models.json 600   # contains an API key → owner-only
seed AGENTS.md   644

exec "$@"