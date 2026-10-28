#!/bin/sh
set -eu

# legacy iptables where the host kernel lacks nf_tables
if ! iptables -nL >/dev/null 2>&1 && iptables-legacy -nL >/dev/null 2>&1; then
	update-alternatives --quiet --set iptables /usr/sbin/iptables-legacy
	update-alternatives --quiet --set ip6tables /usr/sbin/ip6tables-legacy
fi

# cgroup v2: leave the root group and hand its controllers down, or nested
# containers cannot take --memory or --cpus (moby's hack/dind does the same)
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
	mkdir -p /sys/fs/cgroup/init
	xargs -rn1 </sys/fs/cgroup/cgroup.procs >/sys/fs/cgroup/init/cgroup.procs 2>/dev/null || :
	sed -e 's/ / +/g' -e 's/^/+/' </sys/fs/cgroup/cgroup.controllers \
		>/sys/fs/cgroup/cgroup.subtree_control
fi

# own session: dumb-init signals only the runner's group, so dockerd
# outlives the job's cancel
setsid dockerd --group docker >/var/log/dockerd.log 2>&1 &
n=0
until docker info >/dev/null 2>&1; do
	n=$((n + 1))
	if [ "$n" -ge 60 ]; then
		cat /var/log/dockerd.log >&2
		exit 1
	fi
	sleep 1
done

# kept out of argv; the runner reads it from the env and masks it
if [ $# -eq 0 ]; then
	: "${ACTIONS_RUNNER_INPUT_JITCONFIG:?no jit config}"
	set -- ./run.sh
fi
cd /home/runner
exec setpriv --reuid=runner --regid=runner --init-groups \
	env HOME=/home/runner USER=runner LOGNAME=runner "$@"
