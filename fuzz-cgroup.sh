#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

function CreateCgroup() {
  local name=$cgdomain/${1?}
  local pid=${2?}

  # put all fuzzers under 1 sub group
  if [[ ! -d $cgdomain ]]; then
    mkdir $cgdomain
    echo "+cpu +cpuset +memory" >$cgdomain/cgroup.subtree_control

    # 4 vCPU for all
    echo "$((4 * 100))" >$cgdomain/cpu.weight
    echo "$((4 * 100000)) 100000" >$cgdomain/cpu.max
    echo "40G" >$cgdomain/memory.max
    echo "20G" >$cgdomain/memory.swap.max
  fi

  mkdir $name || return 13
  echo "$pid" >$name/cgroup.procs
  # 1 vCPU per fuzzer
  echo "$((100 * 1))" >$name/cpu.weight
  echo "$((100000 * 1))" >$name/cpu.max
  echo "8G" >$name/memory.max
  echo "0G" >$name/memory.swap.max
}

function KillCgroup() {
  local name=$cgdomain/${1?}

  if grep -q 'populated 0' $name/cgroup.events; then
    rmdir $name
  else
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
  CreateCgroup $1 $2
elif [[ $# -eq 1 ]]; then
  KillCgroup $1
fi
