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
        if grep -q 'crashes' $tmpfile; then
          echo -e "\n new crash(s) found for $b\n"
        else
          echo -e "\n new hang(s) found for $b\n"
        fi
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
    if tail -v -n 7 $i | colourStrip | grep -F -B 7 -A 7 -e 'PROGRAM ABORT' -e 'Testing aborted' -e '+++ Baking aborted programmatically +++'; then
      local d=$(dirname $i)
      echo " $d finished"
      if grep -F 'Statistics:' $d/fuzz.log | grep -v ', 0 crashes saved' >&2; then
        echo -e "\n $d contains CRASHes !!!\n" >&2
      fi
      if [[ ! -d $fuzzdir/aborted ]]; then
        mkdir -p $fuzzdir/aborted
      fi
      mv $d $fuzzdir/aborted
      sudo $(dirname $0)/fuzz-cgroup.sh $(basename $d) # kill it
    fi
  done

  for i in $(ls $fuzzdir/*/default/fuzzer_stats 2>/dev/null); do
    local d=$(dirname $(dirname $i))
    local pid=$(awk '/^fuzzer_pid/ { print $3 }' $i)
    if [[ -n $pid ]]; then
      if ! kill -0 $pid 2>/dev/null; then
        echo " $d is dead (pid=$pid)" >&2
        if [[ ! -d $fuzzdir/died ]]; then
          mkdir -p $fuzzdir/died
        fi
        mv $d $fuzzdir/died
        sudo $(dirname $0)/fuzz-cgroup.sh $(basename $d) # delete Cgroup
      fi
    else
      echo -e "$d is in an unexpected state and has no pid" >&2
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
    while read -r exe input_dir add; do
      if ! ls -d $cgdomain/${software}_${exe}_* &>/dev/null; then
        if ! ls -d $fuzzdir/aborted/${software}_${exe}_* &>/dev/null; then
          target=$tmpdir/next.1st
        else
          target=$tmpdir/next.2nd
        fi
      else
        target=$tmpdir/next.3rd
      fi
      echo "$exe $input_dir $add" >>$target
    done
  cat $tmpdir/next.{1st,2nd,3rd} 2>/dev/null
}

function runFuzzers() {
  local wanted=${1?}
  local running=$(ls -d $fuzzdir/${software}_* 2>/dev/null | wc -w)

  local delta=$((wanted - running))

  if [[ $delta -gt 0 ]]; then
    echo -en "\n starting $delta x $software: "

    if softwareWasCloned || softwareWasUpdated; then
      cd ~/sources/$software || return 1
      echo -e "\n building $software ...\n"
      buildSoftware
    fi

    local tmpdir
    tmpdir=$(mktemp -d /tmp/$(basename $0)_XXXXXX)
    getFuzzerCandidates |
      head -n $delta |
      while read -r line; do
        if ! startAFuzzer $line; then
          echo -e "\n an issue occured for $line\n" >&2
          return 1
        fi
      done
    rm -rf $tmpdir
    echo -e "\n\n"

  elif [[ $delta -lt 0 ]]; then
    ((delta = -delta))
    echo "stopping $delta x $software: "
    ls -d $cgdomain/${software}_* 2>/dev/null |
      shuf -n $delta |
      while read -r d; do
        fuzzer=$(basename $d)
        statfile=$fuzzdir/$fuzzer/default/fuzzer_stats
        # stat file is not immediately filled after fuzzer start
        if [[ -s $statfile ]]; then
          pid=$(awk '/^fuzzer_pid / { print $3 }' $statfile)
          echo -n "    pid from fuzzer_stats of $fuzzer: $pid "
          kill -15 $pid
          echo
        else
          pids=$(cat $d/cgroup.procs)
          if [[ -n $pids ]]; then
            echo -n "    kill cgroup tasks of $fuzzer: $pids"
            xargs -n 1 kill -15 <<<$pids
          fi
        fi
        sudo $(dirname $0)/fuzz-cgroup.sh $fuzzer # kill it
      done
    echo -e "\n\n"
  fi
}

function startAFuzzer() {
  local fuzzer=${1?}
  local exe=${2?}
  local input_dir=${3?}
  shift 3
  local add=${*-}

  cd ~/sources/$software

  local fuzz_dirname=${software}_${fuzzer}_$(date +%Y%m%d-%H%M%S)_$(getCommitId)
  local output_dir=$fuzzdir/$fuzz_dirname
  mkdir -p $output_dir

  cp $exe $output_dir
  # for the reproducer needed
  if [[ $software == "openssl" ]]; then
    cp ${exe}-test $output_dir
  fi

  cd $output_dir
  export AFL_TMPDIR=$output_dir
  nice -n 3 /usr/bin/afl-fuzz -i $input_dir -o ./ $add -I $0 -- ./$(basename $exe) &>./fuzz.log &
  local pid=$!
  echo -e "\n    started: $fuzzer (pid=$pid)\n"
  sudo $(dirname $0)/fuzz-cgroup.sh $fuzz_dirname $pid # create it
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

# affects the run of a fuzzer
export AFL_MAP_SIZE=70144
export PERFORMANCE=1

# log file readability
export AFL_NO_COLOUR=1
export ALWAYS_COLORED=0
export USE_COLOR=0

if [[ $# -eq 0 ]]; then
  echo ' a parameter is required' >&2
  exit 1
fi

lck=/tmp/$(basename $0).lock
lock
trap cleanUp INT QUIT TERM EXIT

fuzzdir="/tmp/torproject/fuzzing"
cgdomain="/sys/fs/cgroup/fuzzing"

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
