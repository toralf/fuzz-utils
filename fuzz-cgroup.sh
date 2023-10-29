#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# helper to put given fuzzer PID under CGroup control

# the "local" cgroup could be further limited, e.g. by https://github.com/toralf/tinderbox/blob/master/bin/cgroup.sh
function PutIntoCgroup() {
  local name=/local/fuzz/${1?}
  local pid=${2?}

  if ! cgcreate -g cpu,memory:$name; then
    return 1
  fi

  # slice is 10us
  cgset -r cpu.cfs_quota_us=105000 $name
  cgset -r memory.limit_in_bytes=20G $name
  cgset -r memory.memsw.limit_in_bytes=30G $name

  for i in cpu memory; do
    echo 1 >/sys/fs/cgroup/$i/$name/notify_on_release
    if ! echo "$pid" >/sys/fs/cgroup/$i/$name/tasks; then
      echo " could not cgroup $pid for $i" >&2
      return 1
    fi
  done
}

#######################################################################
#
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root "
  exit 1
fi

if [[ $# -ne 2 ]]; then
  echo " wrong # of args"
  exit 1
fi

owner=$(ps -o user= -p $2)
if [[ $owner != "torproject" ]]; then
  echo " wrong owner '$owner' for pid $2"
  exit 1
fi

export CGROUP_LOGLEVEL=ERROR
PutIntoCgroup $1 $2
