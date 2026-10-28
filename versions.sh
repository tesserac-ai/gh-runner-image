#!/bin/sh
# prints the build args as KEY=value; needs an authenticated gh, curl and jq
set -eu

latest() {
	gh api "repos/$1/releases/latest" --jq .tag_name | sed 's/^v//'
}

# the sha256 github computed for a release asset
digest() {
	gh api "repos/$1/releases/tags/$2" \
		--jq ".assets[] | select(.name == \"$3\") | .digest" | sed 's/^sha256://'
}

runner=$(latest actions/runner)
python=$(gh api -H 'Accept: application/vnd.github.raw' \
	repos/actions/python-versions/contents/versions-manifest.json \
	| jq -c '[.[] | select(.stable) | . as $r | .files[]
		| select(.filename == "python-\($r.version)-linux-26.04-x64.tar.gz")
		| {version: $r.version, url: .download_url, file: .filename}][0]')
py_url=$(printf '%s' "$python" | jq -r .url)
py_tag=$(printf '%s' "$py_url" | sed -E 's|.*/releases/download/([^/]+)/.*|\1|')

out=$(cat <<EOF
RUNNER_VERSION=$runner
RUNNER_SHA256=$(digest actions/runner "v$runner" "actions-runner-linux-x64-$runner.tar.gz")
GH_VERSION=$(latest cli/cli)
NODE_VERSION=$(curl -fsSL https://nodejs.org/dist/index.json \
	| jq -r '[.[] | select(.lts)][0].version' | sed 's/^v//')
GO_VERSION=$(curl -fsSL 'https://go.dev/dl/?mode=json' | jq -r '.[0].version' | sed 's/^go//')
PYTHON_VERSION=$(printf '%s' "$python" | jq -r .version)
PYTHON_URL=$py_url
PYTHON_SHA256=$(digest actions/python-versions "$py_tag" "$(printf '%s' "$python" | jq -r .file)")
EOF
)

if printf '%s\n' "$out" | grep -E '=(null)?$' >&2; then
	echo "unresolved" >&2
	exit 1
fi
printf '%s\n' "$out"
