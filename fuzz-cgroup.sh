#!/bin/sh
# set -x

# helper to put given fuzzer PID under CGroup control


# needed for this to work: https://github.com/toralf/tinderbox/blob/master/bin/cgroup.sh
function PutIntoCgroup() {
  local name=local/$1
  local pid=$2

  # use cgroup v1 if available
  if ! hash -r cgcreate || ! hash -r cgset || ! test -d /sys/fs/cgroup; then
    return 0
  fi

  if ! cgcreate -g cpu,memory:$name; then
    return 1
  fi

  cgset -r cpu.cfs_quota_us=105000          $name
  cgset -r memory.limit_in_bytes=20G        $name
  cgset -r memory.memsw.limit_in_bytes=30G  $name

  for i in cpu memory
  do
    echo 1 > /sys/fs/cgroup/$i/$name/notify_on_release
    if ! echo "$pid" > /sys/fs/cgroup/$i/$name/tasks; then
      return 1
    fi
  done
}


function RemoveCgroup() {
  local name=local/$1

  cgdelete cpu,memory:$name
}


#######################################################################
#
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 1
fi

if [[ $# -ne 2 ]]; then
  echo "wrong # of args"
  exit 1
fi

if ! PutIntoCgroup $1 $2; then
  echo " PutIntoCgroup failed: $@"
  RemoveCgroup $1
  exit 1
fi
