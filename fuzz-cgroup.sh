#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

function CreateCgroup() {
  local name=$cgdomain/${1?}
  local pid=${2?}

  # put all fuzzers under 1 sub group
  if [[ ! -d $cgdomain ]]; then
    if mkdir $cgdomain 2>/dev/null; then
      echo "+cpu +cpuset +memory" >$cgdomain/cgroup.subtree_control

      # 2 vCPU for all fuzzers
      echo "$((2 * 100))" >$cgdomain/cpu.weight
      echo "$((2 * 100000))" >$cgdomain/cpu.max
      echo "2G" >$cgdomain/memory.max
      echo "20G" >$cgdomain/memory.swap.max # stdout of the fuzzer is counted b/c it goes to a tmpfs
    fi
  fi

  if ! mkdir $name; then
    echo " cannot create cgroup $name for pid $pid" 2>&1
    return 13
  fi

  echo "$pid" >$name/cgroup.procs
  # 1 vCPU per fuzzer
  echo "$((1 * 100))" >$name/cpu.weight
  echo "$((1 * 100000))" >$name/cpu.max
  echo "1G" >$name/memory.max
}

function RemoveCgroup() {
  local name=$cgdomain/${1?}

  if [[ -d $name ]]; then
    sleep 1
    if grep -q 'populated 0' $name/cgroup.events 2>/dev/null; then
      rmdir $name
    else
      echo " cannot remove cgroup $name, procs: $(cat $name/cgroup.procs | xargs)"
      return 1
    fi
  fi
}

#######################################################################
#
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root " >&2
  exit 1
fi

cgdomain="/sys/fs/cgroup/fuzzing"

if [[ $# -eq 2 ]]; then
  pid_user=$(ps -o user= -p $2)
  if [[ $pid_user == "torproject" ]]; then
    if ! CreateCgroup $1 $2; then
      RemoveCgroup $1
      exit 1
    fi
  else
    echo " pid $2 belongs to $pid_user" >&2
    exit 1
  fi
elif [[ $# -eq 1 ]]; then
  RemoveCgroup $1
fi
