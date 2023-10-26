#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# start/stop AFL fuzzers, check for findings, plot metrics and more

function checkForFindings() {
  ls -d $fuzzdir/*_*_*-*_* 2>/dev/null |
    while read -r d; do
      b=$(basename $d)
      tar_archive=~/findings/$b.tar.gz # GH issue tracker does not allow *.xz attachments
      options=""
      if [[ -s $tar_archive ]]; then
        options="-newer $tar_archive"
      fi

      tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX)
      find $d -wholename "*/default/crashes/*" -o -wholename "*/default/hangs/*" $options >$tmpfile
      if [[ -s $tmpfile ]]; then
        echo -e "\n new findings for $b\n"
        rsync --archive --exclude '*/queue/*' --exclude '*/.synced/*' --verbose $d ~/findings/
        echo
        chmod -R g+r ~/findings/$b
        find ~/findings/$b -type d -exec chmod g+x {} +
        tar -C ~/findings/ -czpf $tar_archive ./$b
        ls -lh $tar_archive
        echo
      fi
      rm $tmpfile
    done

  for i in $(ls $fuzzdir/*/fuzz.log 2>/dev/null); do
    if tail -v -n 7 $i | colourStrip | grep -B 10 -A 10 -e 'PROGRAM ABORT' -e 'Testing aborted'; then
      local d
      d=$(dirname $i)
      echo " $d is aborted"
      mv $d $fuzzdir/aborted
    fi
  done

  for i in $(ls $fuzzdir/*/default/fuzzer_stats 2>/dev/null); do
    local pid
    pid=$(grep "^fuzzer_pid" $i | awk '{ print $3 }')
    if ! kill -0 $pid 2>/dev/null; then
      local d
      d=$(dirname $(dirname $i))
      echo " OOPS: $d is not running"
      mv $d $fuzzdir/aborted
    fi
  done

  return 0
}

function cleanUp() {
  local rc=${1:-$?}
  trap - INT QUIT TERM EXIT

  rm -f "$lck"
  exit $rc
}

function colourStrip() {
  if [[ -x /usr/bin/ansifilter ]]; then
    ansifilter
  else
    cat
  fi
}

function getCommitId() {
  git log --max-count=1 --pretty=format:%H | cut -c 1-12
}

function lock() {
  if [[ -s $lck ]]; then
    if kill -0 $(cat $lck) 2>/dev/null; then
      return 1 # valid
    else
      echo -n " ignored stalled lock file $lck: "
      cat $lck
    fi
  fi
  echo "$(date) $$" >$lck || exit 1
}

function plotData() {
  for d in $(ls -d $fuzzdir/*/default/ 2>/dev/null); do
    afl-plot $d $(dirname $d) &>/dev/null
  done
}

function repoWasUpdated() {
  cd $1 || return 1
  local old
  old=$(getCommitId)
  git pull 1>/dev/null
  local new
  new=$(getCommitId)
  [[ $old != "$new" ]]
}

function getFuzzerCandidates() {
  # prefer a "non-running non-aborted" (1st) over a "non-running but aborted" (2nd), but choose at least one (3rd)
  getFuzzers $software |
    shuf |
    while read -r exe idir add; do
      if ! ls -d /sys/fs/cgroup/cpu/local/fuzz/${software}_${exe}_* &>/dev/null; then
        if ! ls -d $fuzzdir/aborted/${software}_${exe}_* &>/dev/null; then
          target=$tmpdir/next.1st
        else
          target=$tmpdir/next.2nd
        fi
      else
        target=$tmpdir/next.3rd
      fi
      echo "$exe $idir $add" >>$target
    done
  cat $tmpdir/next.{1st,2nd,3rd} 2>/dev/null
}

function runFuzzers() {
  local wanted=${1?}
  local running
  running=$(ls -d /sys/fs/cgroup/cpu/local/fuzz/${software}_* 2>/dev/null | wc -w)

  local delta
  if ! ((delta = wanted - running)); then
    return 0
  fi

  if [[ $delta -gt 0 ]]; then
    if softwareWasCloned || softwareWasUpdated; then
      cd ~/sources/$software || return 1
      echo -e "\n building $software ...\n"
      buildSoftware
    fi

    echo -en "\n starting $delta fuzzer(s) for $software: "
    local tmpdir
    tmpdir=$(mktemp -d /tmp/$(basename $0)_XXXXXX)
    getFuzzerCandidates |
      head -n $delta |
      while read -r line; do
        startAFuzzer $line
      done
    rm -rf $tmpdir

  else
    ((delta = delta))
    echo "stopping $delta $software: "
    ls -d /sys/fs/cgroup/cpu/local/fuzz/${software}_* 2>/dev/null |
      shuf -n $delta |
      while read -r d; do
        # file is not immediately available
        fuzzer=$(basename $d)
        statfile=$fuzzdir/$fuzzer/default/fuzzer_stats
        if [[ -s $statfile ]]; then
          pid=$(awk '/^fuzzer_pid / { print $3 }' $statfile)
          echo -n "    pid from fuzzer_stats of $fuzzer: $pid "
          kill -15 $pid
          echo
        else
          tasks=$(cat $d/tasks)
          echo -n "    cgroup ($fuzzer): $tasks"
          kill -15 $tasks
        fi
      done
  fi
  echo -e "\n\n"
}

function startAFuzzer() {
  local fuzzer=${1?:name ?!}
  local exe=${2?:exe ?!}
  local idir=${3?:idir ?!}
  shift 3
  local add=${*-}

  cd ~/sources/$software

  local fdir=${software}_${fuzzer}_$(date +%Y%m%d-%H%M%S)_$(getCommitId)
  local odir=$fuzzdir/$fdir
  mkdir -p $odir

  cp $exe $odir
  # TODO: move this quirk to fuzz-lib-openssl.sh ?
  if [[ $software == "openssl" ]]; then
    cp ${exe}-test $odir
  fi

  # use a tmpfs instead of the device
  export AFL_TMPDIR=$odir

  cd $odir

  nice -n 3 /usr/bin/afl-fuzz -i $idir -o ./ $add -I $0 -- ./$(basename $exe) &>./fuzz.log &
  local pid=$!
  echo -n "    $fuzzer"
  if ! sudo $(dirname $0)/fuzz-cgroup.sh $fdir $pid; then
    echo " sth went wrong, killing $pid ..." >&2
    kill -15 $pid
    sleep 5
    if kill -0 $pid; then
      kill -9 $pid
    fi
  fi
}

#######################################################################
#
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

export GIT_PAGER="cat"
export PAGER="cat"

export CC="/usr/bin/afl-clang-fast"
export CXX="${CC}++"
export CFLAGS="-O2 -pipe -march=native"
export CXXFLAGS="$CFLAGS"

# effective at compile time
export AFL_QUIET=1

# affects the start of a fuzzer
export AFL_EXIT_WHEN_DONE=1
export AFL_HARDEN=1
export AFL_SKIP_CPUFREQ=1
export AFL_SHUFFLE_QUEUE=1

# affects the run of an instrumented fuzzer
export AFL_MAP_SIZE=70144

# log file readability
export AFL_NO_COLOUR=1

if [[ $# -eq 0 ]]; then
  echo ' a parameter is required' >&2
  exit 1
fi

lck=/tmp/$(basename $0).lock
lock
trap cleanUp INT QUIT TERM EXIT

fuzzdir="/tmp/torproject/fuzzing"
if [[ ! -d $fuzzdir/aborted ]]; then
  mkdir -p $fuzzdir/aborted
fi

while getopts fo:pt: opt; do
  case $opt in
  f)
    checkForFindings
    ;;
  o)
    software="openssl"
    # shellcheck source=./fuzz-lib-openssl.sh
    source $(dirname $0)/fuzz-lib-${software}.sh
    runFuzzers "$OPTARG"
    ;;
  p)
    plotData
    ;;
  t)
    software="tor"
    # shellcheck source=./fuzz-lib-tor.sh
    source $(dirname $0)/fuzz-lib-${software}.sh
    runFuzzers "$OPTARG"
    ;;
  *)
    echo " sth wrong" >&2
    exit 1
    ;;
  esac
done
