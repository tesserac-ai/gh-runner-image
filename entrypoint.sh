#!/bin/sh
# one job: start this container's own dockerd, then the runner as uid 1001
set -eu

jit=${ACTIONS_RUNNER_INPUT_JITCONFIG:?no jit config}
unset ACTIONS_RUNNER_INPUT_JITCONFIG

# the host's netfilter decides: nft where the kernel speaks it, legacy otherwise
if ! iptables -nL >/dev/null 2>&1 && iptables-legacy -nL >/dev/null 2>&1; then
	update-alternatives --quiet --set iptables /usr/sbin/iptables-legacy
	update-alternatives --quiet --set ip6tables /usr/sbin/ip6tables-legacy
fi

dockerd --group docker >/var/log/dockerd.log 2>&1 &
n=0
until docker info >/dev/null 2>&1; do
	n=$((n + 1))
	if [ "$n" -ge 60 ]; then
		cat /var/log/dockerd.log >&2
		exit 1
	fi
	sleep 1
done

cd /home/runner
exec setpriv --reuid=runner --regid=runner --init-groups \
	env HOME=/home/runner USER=runner LOGNAME=runner \
	./run.sh --jitconfig "$jit"
