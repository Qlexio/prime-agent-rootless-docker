# syntax=docker/dockerfile:1
FROM ubuntu:26.04

ARG AGENT_USER=agent
ARG AGENT_UID=53046
ARG AGENT_GID=53046
# Paste the exact install command from the README here, or pass it with --build-arg
ARG PRIME_INSTALL_CMD="curl -fsSL https://app.primeintellect.ai/prime-agent/install.sh | sh"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=Etc/UTC

# --- OS dependencies -------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv python3-dev \
        build-essential \
        git curl ca-certificates \
        tini \
        less nano procps \
    && rm -rf /var/lib/apt/lists/*

# --- uv (static binaries from the official image) ---------------------------
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# --- Remove Ubuntu user -----------------------------------------------------
RUN userdel -r ubuntu 2>/dev/null || true

# --- Non-standard user -----------------------------------------------------
RUN groupadd --gid ${AGENT_GID} ${AGENT_USER} \
 && useradd  --uid ${AGENT_UID} --gid ${AGENT_GID} \
             --create-home --home-dir /home/${AGENT_USER} \
             --shell /bin/bash ${AGENT_USER} \
 && mkdir -p /workspace \
 && chown ${AGENT_UID}:${AGENT_GID} /workspace

# --- uv defaults for the agent -----------------------------------------------
ENV UV_LINK_MODE=copy \
    UV_CACHE_DIR=/home/${AGENT_USER}/.cache/uv \
    PRIME_CFG_DIR=/home/${AGENT_USER}/.prime/agent \
    VIRTUAL_ENV=${PRIME_CFG_DIR}/kernel-venv \
    PATH=/home/${AGENT_USER}/.local/bin:${PATH} \
    PRIME_INSTALL_CMD=${PRIME_INSTALL_CMD}

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 prime-setup.sh   /usr/local/bin/prime-setup
# Defaults seeded on first run (read-only templates)
COPY defaults/ /opt/prime-defaults/
RUN chmod 644 /opt/prime-defaults/*

USER ${AGENT_USER}
WORKDIR /workspace

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]