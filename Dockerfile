# syntax=docker/dockerfile:1
# no pins: versions.sh hands in the newest stable release of each, and CI
# rebuilds every night, so the runner never falls behind GitHub's 30 days
FROM ubuntu:26.04

ARG RUNNER_VERSION
ARG RUNNER_SHA256
ARG DOCKER_VERSION
ARG BUILDX_VERSION
ARG COMPOSE_VERSION
ARG GH_VERSION
ARG NODE_VERSION
ARG PYTHON_VERSION
ARG GO_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    ImageOS=ubuntu26 \
    RUNNER_TOOL_CACHE=/opt/hostedtoolcache \
    AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache \
    RUNNER_MANUALLY_TRAP_SIG=1 \
    ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential ca-certificates curl dumb-init git git-lfs gnupg iptables \
       jq libicu78 libssl3t64 locales lsb-release make openssh-client pkg-config \
       python3 python3-pip python3-venv rsync shellcheck sudo tzdata unzip \
       xz-utils zip zstd \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 123 docker \
    && useradd --uid 1001 --create-home --shell /bin/bash --groups docker,sudo runner \
    && echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner \
    && chmod 0440 /etc/sudoers.d/runner

WORKDIR /tmp/dl

RUN curl -fsSLo runner.tgz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    && echo "${RUNNER_SHA256}  runner.tgz" | sha256sum -c - \
    && tar -xzf runner.tgz -C /home/runner \
    && chown -R runner:runner /home/runner \
    && rm ./*

RUN curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" \
    | tar -xz --strip-components=1 -C /usr/bin \
    && curl -fsSLO "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-amd64" \
    && curl -fsSL "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/checksums.txt" \
       | grep " \*\?buildx-v${BUILDX_VERSION}.linux-amd64$" | sha256sum -c - \
    && curl -fsSLO "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    && curl -fsSL "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-x86_64.sha256" \
       | sha256sum -c - \
    && install -D -m 0755 "buildx-v${BUILDX_VERSION}.linux-amd64" /usr/local/lib/docker/cli-plugins/docker-buildx \
    && install -D -m 0755 docker-compose-linux-x86_64 /usr/local/lib/docker/cli-plugins/docker-compose \
    && rm ./*

RUN curl -fsSLO "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_checksums.txt" \
       | grep " gh_${GH_VERSION}_linux_amd64.tar.gz$" | sha256sum -c - \
    && tar -xzf "gh_${GH_VERSION}_linux_amd64.tar.gz" --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION}_linux_amd64/bin/gh" \
    && rm ./*

# the layout setup-node, setup-python and setup-go look in; a version
# without its .complete marker counts as missing
RUN d="/opt/hostedtoolcache/node/${NODE_VERSION}/x64" \
    && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" \
       | grep " node-v${NODE_VERSION}-linux-x64.tar.xz$" | sha256sum -c - \
    && mkdir -p "$d" && tar -xJf "node-v${NODE_VERSION}-linux-x64.tar.xz" --strip-components=1 -C "$d" \
    && touch "$d.complete" \
    && d="/opt/hostedtoolcache/go/${GO_VERSION}/x64" \
    && curl -fsSLO "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    && curl -fsSL "https://go.dev/dl/?mode=json&include=all" \
       | jq -r --arg f "go${GO_VERSION}.linux-amd64.tar.gz" '.[].files[] | select(.filename == $f) | "\(.sha256)  \($f)"' \
       | sha256sum -c - \
    && mkdir -p "$d" && tar -xzf "go${GO_VERSION}.linux-amd64.tar.gz" --strip-components=1 -C "$d" \
    && touch "$d.complete" \
    && rm ./*

# setup.sh installs into $AGENT_TOOLSDIRECTORY from its own directory
RUN url=$(curl -fsSL https://raw.githubusercontent.com/actions/python-versions/main/versions-manifest.json \
       | jq -r --arg f "python-${PYTHON_VERSION}-linux-26.04-x64.tar.gz" '.[].files[] | select(.filename == $f) | .download_url') \
    && curl -fsSL "$url" | tar -xz \
    && bash setup.sh \
    && rm -rf ./* \
    && chown -R runner:runner /opt/hostedtoolcache

WORKDIR /home/runner

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# dockerd needs a real filesystem for overlay2; --rm drops the volume with the job
VOLUME /var/lib/docker

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/entrypoint.sh"]
