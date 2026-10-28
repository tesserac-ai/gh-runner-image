#!/bin/bash
# runs as the runner user through the entrypoint, see README
set -euo pipefail

echo "user $(id -un) $(id -u), groups $(id -Gn)"
env -u ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT ./config.sh --version
docker version --format 'docker {{.Server.Version}}'
docker buildx version
docker compose version
gh --version | head -1
git --version
git lfs version
shellcheck --version | sed -n 2p
make --version | head -1
zstd --version
jq --version
tc=/opt/hostedtoolcache
ls "$tc"/{node,go,Python}/*/x64.complete
mkdir "$tc/w"
rmdir "$tc/w"
node=("$tc"/node/*/x64/bin/node) go=("$tc"/go/*/x64/bin/go) py=("$tc"/Python/*/x64/bin/python3)
"${node[0]}" --version
"${go[0]}" version
"${py[0]}" --version
"${py[0]}" -m pip cache dir
sudo -n true

docker run --rm --memory 64m --cpus 0.5 busybox true
printf 'FROM busybox\nRUN echo built > /x\n' | docker buildx build -q --load -t smoke - >/dev/null
docker run --rm smoke cat /x

cd "$(mktemp -d)"
cat >compose.yaml <<'EOF'
services:
  web:
    image: busybox
    command: httpd -f -p 8080
    mem_limit: 64m
  probe:
    image: busybox
    command: timeout 20 sh -c 'until nc -z web 8080; do sleep 1; done; echo compose ok'
    depends_on: [web]
EOF
docker compose up --abort-on-container-exit --exit-code-from probe probe
docker compose down -t 1
echo smoke ok
