# gh-runner-image

The container image behind tesserac-ai's self-hosted GitHub Actions runners
on `runner1` (pve2). One container per job: the entrypoint starts the
container's own `dockerd`, then the runner from a just-in-time config, and the
container is gone with the job. The slots that run it live in
`tesserac-infra`, role `gh_runner`.

Ubuntu 26.04 with what the org's workflows expect from `ubuntu-latest`
without a setup action: git, git-lfs, gh, jq, make, build-essential, rsync,
shellcheck, zstd, python3, docker with buildx and compose, passwordless sudo
for uid 1001. The newest Node LTS, Python and Go sit in
`/opt/hostedtoolcache`, so `setup-node`, `setup-python` and `setup-go` find
them without a download; any other version they fetch per job.

Nothing is pinned. `versions.sh` resolves the newest stable release of each
part, the build checks every download against its upstream checksum, and the
workflow builds, smoke-tests and pushes `ghcr.io/tesserac-ai/gh-runner-image`
every night. GitHub refuses jobs to a runner more than 30 days behind its
newest release; a nightly build keeps it a day behind at most.

Tags: `latest`, the runner version, and the runner version with the build
date.

The container runs `--privileged`, which its own `dockerd` needs. A job that
wants to can leave it for the VM; the VM is the trust boundary, not the
container.

Build and test locally:

```sh
docker build $(./versions.sh | sed 's/^/--build-arg /') -t gh-runner:test .
docker run --rm --privileged -v "$PWD/test/smoke.sh:/smoke.sh:ro" \
  --entrypoint /usr/bin/dumb-init gh-runner:test -- bash /smoke.sh
```
