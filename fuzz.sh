#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# wrapper for https://github.com/AFLplusplus/AFLplusplus to fuzz (currently) Tor and OpenSSL

function checkForFindings() {
  ls -d $fuzzdir/*_*_*-*_* 2>/dev/null |
    while read -r d; do
      b=$(basename $d)
      tar_archive=~/findings/$b.tar.gz # GitHub issue tracker does not accept xz compressed files
      options=""
      if [[ -s $tar_archive ]]; then
        options="-newer $tar_archive"
      fi

      tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX)
      find $d -wholename "*/default/crashes/*" -o -wholename "*/default/hangs/*" $options >$tmpfile
      if [[ -s $tmpfile ]]; then
        if grep -q 'crashes' $tmpfile; then
          echo -e "\n new CRASH(s) found for $b\n"
        elif grep -q 'hangs' $tmpfile; then
          echo -e "\n new hang(s) found for $b\n"
        else
          echo "woops: $tmpfile" >&2
          exit 1
        fi

        echo -e "\n reproducer:\n\n cd ~/findings/$b\n for i in \$(ls ./default/{crashes,hangs}/* 2>/dev/null); do time ./*-test \$i; echo; done\n\n"

        # retry to handle races
        n=5
        while ((n--)); do
          if rsync --archive --exclude '*/queue/*' --exclude '*/.synced/*' --verbose $d ~/findings/; then
            echo
            break
          fi
        done
        chmod -R g+r ~/findings/$b
        find ~/findings/$b -type d -exec chmod g+x {} +
        tar -C ~/findings/ -czpf $tar_archive ./$b
        ls -lh $tar_archive
        echo
      fi
      rm $tmpfile
    done
}

function checkForAborts() {
  ls $fuzzdir/*/fuzz.log 2>/dev/null |
    while read -r log; do
      if tail -v -n 7 $log | colourStrip | grep -B 17 -A 7 -e 'PROGRAM ABORT' -e '.* aborted' -e 'Have a nice day'; then
        d=$(dirname $log)
        echo " $d aborted"
        if grep -F 'Statistics:' $log | grep -v ', 0 crashes saved'; then
          echo -e "\n $d contains CRASH(s) !!!\n"
        fi
        if [[ ! -d $fuzzdir/aborted ]]; then
          mkdir -p $fuzzdir/aborted
        fi
        if sudo $(dirname $0)/fuzz-cgroup.sh $(basename $d); then
          gzip $log
          mv $d $fuzzdir/aborted
        fi
      fi
    done

  ls -d $fuzzdir/*_*_*-*_* 2>/dev/null |
    while read -r d; do
      pid=$(awk '/^fuzzer_pid/ { print $3 }' $d/default/fuzzer_stats 2>/dev/null)
      if [[ ! -s $d/fuzz.log || -z $pid ]] || ! grep -q $pid $cgdomain/$(basename $d)/cgroup.procs; then
        echo -e "\n $d is DEAD (pid=$pid)\n"
        if [[ ! -d $fuzzdir/died ]]; then
          mkdir -p $fuzzdir/died
        fi
        if ! sudo $(dirname $0)/fuzz-cgroup.sh $(basename $d); then
          echo -en " killing pids: "
          tac $cgdomain/$(basename $d)/cgroup.procs | tee | xargs -n 1 -r kill -9
          sleep 2
          sudo $(dirname $0)/fuzz-cgroup.sh $(basename $d)
        fi
        gzip $d/fuzz.log
        mv $d $fuzzdir/died
      fi
    done
}

function cleanUp() {
  local rc=${1:-$?}
  trap - INT QUIT TERM EXIT

  rm -- $lck
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
      ls -l $lck
    fi
  fi
  echo "$$" >$lck || exit 1
}

function plotData() {
  for d in $(ls -d $fuzzdir/*/default/ 2>/dev/null); do
    afl-plot $d $(dirname $d) &>/dev/null
  done
}

function repoWasUpdated() {
  cd $1 || exit 1
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
  echo -e "\n$(date)\n    started: $fuzzer (pid=$pid)\n"
  sudo $(dirname $0)/fuzz-cgroup.sh $fuzz_dirname $pid # create it
}

function stopAFuzzer() {
  local fuzzer=${1?}

  local statfile=$fuzzdir/$fuzzer/default/fuzzer_stats
  # stat file is not immediately filled after fuzzer start
  if [[ -s $statfile ]]; then
    local pid=$(awk '/^fuzzer_pid / { print $3 }' $statfile)
    echo -n "    got pid from fuzzer_stats of $fuzzer: $pid "
    kill -15 $pid
    echo
  else
    local pids=$(cat $d/cgroup.procs)
    if [[ -n $pids ]]; then
      echo "   kill cgroup tasks of $fuzzer: $pids"
      xargs -n 1 kill -15 <<<$pids
      sleep 10
      pids=$(cat $d/cgroup.procs)
      if [[ -n $pids ]]; then
        echo "   get roughly with $pids"
        xargs -n 1 kill -9 < <(cat $d/cgroup.procs)
      fi
    else
      echo -n "   got no pid for $d"
    fi
  fi
  if ! sudo $(dirname $0)/fuzz-cgroup.sh $fuzzer; then
    echo -e "\n woops ^^"
  fi
  echo
}

function runFuzzers() {
  local wanted=${1?}
  local running=$(ls -d $fuzzdir/${software}_* 2>/dev/null | wc -w)
  local delta

  if [[ $wanted =~ ^[0-9]+$ ]]; then
    delta=$((wanted - running))
  else
    delta=1
  fi

  if [[ $delta -gt 0 ]]; then
    echo -en "\n$(date)\n job changes: $delta x $software: "

    if [[ $force_build -eq 1 ]] || softwareWasCloned || softwareWasUpdated || ! getFuzzers $software | grep -q '.'; then
      cd ~/sources/$software
      echo -e "\n$(date)\n building $software ...\n"
      buildSoftware
    fi

    local tmpdir
    tmpdir=$(mktemp -d /tmp/$(basename $0)_XXXXXX)
    getFuzzerCandidates |
      if [[ $wanted =~ ^[0-9]+$ ]]; then
        head -n $delta
      else
        grep "^$wanted "
      fi |
      while read -r line; do
        if ! startAFuzzer $line; then
          echo -e "\n$(date)\n cannot start $line\n" >&2
          return 1
        fi
      done
    rm -r $tmpdir

  elif [[ $delta -lt 0 ]]; then
    ((delta = -delta))
    echo -e "\n$(date)\n stopping $delta x $software: "
    ls -dt $cgdomain/${software}_* 2>/dev/null |
      tail -n $delta |
      while read -r d; do
        fuzzer=$(basename $d)
        stopAFuzzer $fuzzer
      done
  fi
}

#######################################################################
#
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(whoami)" != "torproject" ]]; then
  echo " you must be torproject" >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo ' a parameter is required' >&2
  exit 1
fi

lck=/tmp/$(basename $0).lock
lock
trap cleanUp INT QUIT TERM EXIT

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
export AFL_NO_SYNC=1

# log file readability
export AFL_NO_COLOR=1
export ALWAYS_COLORED=0

fuzzdir="/tmp/torproject/fuzzing"
cgdomain="/sys/fs/cgroup/fuzzing"

force_build=0

while getopts abfo:pt: opt; do
  case $opt in
  a) checkForAborts ;;
  b) force_build=1 ;;
  f) checkForFindings ;;
  o)
    software="openssl"
    # shellcheck source=./fuzz-lib-openssl.sh
    source $(dirname $0)/fuzz-lib-${software}.sh
    runFuzzers "$OPTARG"
    ;;
  p) plotData ;;
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
