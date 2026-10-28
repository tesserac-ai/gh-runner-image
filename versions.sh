#!/bin/sh
# prints KEY=value build args: the newest stable release of everything the
# image carries. needs gh (authenticated), curl and jq
set -eu

latest() {
	gh api "repos/$1/releases/latest" --jq .tag_name | sed 's/^v//'
}

body=$(gh api repos/actions/runner/releases/latest --jq '.tag_name + "\n" + .body')

out=$(cat <<EOF
RUNNER_VERSION=$(printf '%s\n' "$body" | head -1 | sed 's/^v//')
RUNNER_SHA256=$(printf '%s\n' "$body" | sed -n 's/.*BEGIN SHA linux-x64 -->\([0-9a-f]\{64\}\)<!--.*/\1/p')
DOCKER_VERSION=$(curl -fsSL https://download.docker.com/linux/static/stable/x86_64/ \
	| grep -o 'docker-[0-9][0-9.]*\.tgz' | sed 's/^docker-//; s/\.tgz$//' | sort -uV | tail -1)
BUILDX_VERSION=$(latest docker/buildx)
COMPOSE_VERSION=$(latest docker/compose)
GH_VERSION=$(latest cli/cli)
NODE_VERSION=$(curl -fsSL https://nodejs.org/dist/index.json \
	| jq -r '[.[] | select(.lts)][0].version' | sed 's/^v//')
PYTHON_VERSION=$(curl -fsSL https://raw.githubusercontent.com/actions/python-versions/main/versions-manifest.json \
	| jq -r '[.[] | select(.stable) | . as $r
		| select(any($r.files[]; .filename == "python-\($r.version)-linux-26.04-x64.tar.gz"))][0].version')
GO_VERSION=$(curl -fsSL 'https://go.dev/dl/?mode=json' | jq -r '.[0].version' | sed 's/^go//')
EOF
)

if printf '%s\n' "$out" | grep -E '=(|null)$' >&2; then
	echo "unresolved" >&2
	exit 1
fi
printf '%s\n' "$out"
