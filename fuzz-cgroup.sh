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

      # 4 vCPU for all fuzzers
      echo "$((4 * 100))" >$cgdomain/cpu.weight
      echo "$((4 * 100000))" >$cgdomain/cpu.max
      echo "8G" >$cgdomain/memory.max
      echo "0" >$cgdomain/memory.swap.max
    fi
  fi

  mkdir $name || return 13
  echo "$pid" >$name/cgroup.procs
  # 1 vCPU per fuzzer
  echo "$((1 * 100))" >$name/cpu.weight
  echo "$((1 * 100000))" >$name/cpu.max
  echo "2G" >$name/memory.max
  echo "0" >$name/memory.swap.max

  echo " created cgroup $name for pid $pid"
}

function RemoveCgroup() {
  local name=$cgdomain/${1?}

  if grep -q 'populated 0' $name/cgroup.events 2>/dev/null; then
    rmdir $name
  else
    echo " cannot remove group $name"
    return 1
  fi
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

cgdomain=/sys/fs/cgroup/fuzzing

if [[ $# -eq 2 ]]; then
  if ! CreateCgroup $1 $2; then
    RemoveCgroup $1
    exit 1
  fi
elif [[ $# -eq 1 ]]; then
  RemoveCgroup $1
fi
