# gh-runner-image

Ephemeral GitHub Actions runner with its own Docker daemon, on Ubuntu 26.04.

## Usage

```sh
docker run --rm --privileged -e ACTIONS_RUNNER_INPUT_JITCONFIG \
    ghcr.io/tesserac-ai/gh-runner-image
```

`ACTIONS_RUNNER_INPUT_JITCONFIG` is the `encoded_jit_config` returned by
`POST /orgs/{org}/actions/runners/generate-jitconfig`. The container starts
`dockerd`, runs one job as uid 1001 and exits.

## Contents

- actions/runner, Docker with buildx and compose, gh
- git, git-lfs, jq, make, build-essential, rsync, shellcheck, wget, zstd,
  python3
- Node LTS, Python and Go in `/opt/hostedtoolcache`
- passwordless sudo

## Build

```sh
docker build $(./versions.sh | sed 's/^/--build-arg /') -t gh-runner .
docker run --rm --privileged -v "$PWD/test/smoke.sh:/smoke.sh:ro" \
    gh-runner bash /smoke.sh
```

`versions.sh` prints the newest release of each component as build
arguments. It needs `gh`, `curl` and `jq`. Downloads are verified: apt by
signature, everything else by sha256.

CI builds nightly and pushes `latest`, `<runner>` and `<runner>-<yyyymmdd>`
with a provenance attestation.

## Security

The container runs privileged. Use it for trusted repositories only.
