#!/bin/bash
# runs inside the image as root: own dockerd, then the tools as the runner user
set -u
if ! iptables -nL >/dev/null 2>&1 && iptables-legacy -nL >/dev/null 2>&1; then
	update-alternatives --quiet --set iptables /usr/sbin/iptables-legacy
	update-alternatives --quiet --set ip6tables /usr/sbin/ip6tables-legacy
	echo "iptables: legacy"
fi
dockerd --group docker >/var/log/dockerd.log 2>&1 &
for _ in $(seq 60); do docker info >/dev/null 2>&1 && break; sleep 1; done
docker info --format 'dockerd {{.ServerVersion}} {{.Driver}}' || { tail -20 /var/log/dockerd.log; exit 1; }
tc=/opt/hostedtoolcache
# shellcheck disable=SC2016 # expands in the runner's shell, not here
setpriv --reuid=runner --regid=runner --init-groups env HOME=/home/runner bash -c '
set -u
cd /home/runner
echo "user $(id -un) $(id -u) groups $(id -Gn)"
env -u ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT ./config.sh --version | sed "s/^/runner /"
docker version --format "client {{.Client.Version}}"
docker buildx version | cut -d" " -f1-2
docker compose version
gh --version | head -1
git --version; git lfs version | cut -d" " -f1
shellcheck --version | sed -n 2p
make --version | head -1; zstd --version; jq --version
'"$tc"'/node/*/x64/bin/node --version
'"$tc"'/go/*/x64/bin/go version
'"$tc"'/Python/*/x64/bin/python3 --version
ls '"$tc"'/*/*/x64.complete
sudo -n true && echo "sudo ok"
docker run --rm busybox:1.37 echo "nested container ok"
printf "FROM busybox:1.37\nRUN echo built > /x\n" | docker build -q -t smoke - >/dev/null && docker run --rm smoke cat /x
'
