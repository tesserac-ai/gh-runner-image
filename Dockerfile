# syntax=docker/dockerfile:1
FROM ubuntu:26.04

LABEL org.opencontainers.image.title=gh-runner-image \
      org.opencontainers.image.description="Ephemeral GitHub Actions runner with its own dockerd, on Ubuntu 26.04" \
      org.opencontainers.image.source=https://github.com/tesserac-ai/gh-runner-image \
      org.opencontainers.image.licenses=MIT

# unpinned: versions.sh hands in the newest releases, ci rebuilds nightly
ARG RUNNER_VERSION
ARG RUNNER_SHA256
ARG GH_VERSION
ARG NODE_VERSION
ARG GO_VERSION
ARG PYTHON_VERSION
ARG PYTHON_URL
ARG PYTHON_SHA256

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    ImageOS=ubuntu26 \
    RUNNER_TOOL_CACHE=/opt/hostedtoolcache \
    AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache \
    RUNNER_MANUALLY_TRAP_SIG=1 \
    ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# gid 123 as in actions/runner's own image; docker-ce keeps an existing group
RUN groupadd --gid 123 docker \
    && useradd --uid 1001 --create-home --shell /bin/bash runner \
    && install -d -o runner -g runner /opt/hostedtoolcache

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSLo /etc/apt/keyrings/docker.asc https://download.docker.com/linux/ubuntu/gpg \
    && gpg --show-keys --with-colons /etc/apt/keyrings/docker.asc \
       | grep -q '^fpr:::::::::9DC858229FC7DD38854AE2D88D81803C0EBFCD88:$' \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu resolute stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential containerd.io docker-buildx-plugin docker-ce docker-ce-cli \
       docker-compose-plugin dumb-init file git git-lfs iproute2 iptables jq \
       libicu78 libssl3t64 lsb-release make openssh-client pkg-config python3 \
       python3-pip python3-venv rsync shellcheck sudo tzdata unzip wget xz-utils \
       zip zstd \
    && rm -rf /var/lib/apt/lists/* \
    && usermod -aG docker,sudo runner \
    && printf '%s\n' 'Defaults env_keep += "DEBIAN_FRONTEND"' 'runner ALL=(ALL) NOPASSWD:ALL' \
       > /etc/sudoers.d/runner \
    && chmod 0440 /etc/sudoers.d/runner

WORKDIR /tmp/dl

RUN curl -fsSLo runner.tgz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    && echo "${RUNNER_SHA256}  runner.tgz" | sha256sum -c - \
    && tar -xzf runner.tgz -C /home/runner \
    && chown -R runner:runner /home/runner \
    && rm ./*

RUN curl -fsSLO "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_checksums.txt" \
       | grep " gh_${GH_VERSION}_linux_amd64.tar.gz$" | sha256sum -c - \
    && tar -xzf "gh_${GH_VERSION}_linux_amd64.tar.gz" --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION}_linux_amd64/bin/gh" \
    && rm ./*

# setup-node and setup-go skip a cached version without its .complete marker
RUN d="/opt/hostedtoolcache/node/${NODE_VERSION}/x64" \
    && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" \
       | grep " node-v${NODE_VERSION}-linux-x64.tar.xz$" | sha256sum -c - \
    && mkdir -p "$d" && tar -xJf "node-v${NODE_VERSION}-linux-x64.tar.xz" --strip-components=1 -C "$d" \
    && touch "$d.complete" && chown -R runner:runner /opt/hostedtoolcache/node \
    && rm ./*

RUN d="/opt/hostedtoolcache/go/${GO_VERSION}/x64" \
    && curl -fsSLO "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    && curl -fsSL "https://go.dev/dl/?mode=json&include=all" \
       | jq -r --arg f "go${GO_VERSION}.linux-amd64.tar.gz" '.[].files[] | select(.filename == $f) | "\(.sha256)  \($f)"' \
       | sha256sum -c - \
    && mkdir -p "$d" && tar -xzf "go${GO_VERSION}.linux-amd64.tar.gz" --strip-components=1 -C "$d" \
    && touch "$d.complete" && chown -R runner:runner /opt/hostedtoolcache/go \
    && rm ./*

# setup.sh copies the working directory into $AGENT_TOOLSDIRECTORY/Python
RUN curl -fsSLo python.tgz "${PYTHON_URL}" \
    && echo "${PYTHON_SHA256}  python.tgz" | sha256sum -c - \
    && tar -xzf python.tgz && rm python.tgz \
    && PIP_NO_CACHE_DIR=1 bash setup.sh \
    && chown -R runner:runner /opt/hostedtoolcache/Python \
    && rm -rf /tmp/dl

WORKDIR /home/runner

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# overlay2 cannot stack on the container's overlayfs; --rm drops the volume
VOLUME /var/lib/docker

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/entrypoint.sh"]
