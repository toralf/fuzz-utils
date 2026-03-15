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
      find $d $options -wholename "*/default/crashes/*" -o -wholename "*/default/hangs/*" >$tmpfile
      if [[ -s $tmpfile ]]; then
        if grep -q 'crashes' $tmpfile; then
          echo -e "\n new CRASH(s) found for $b\n"
        elif grep -q 'hangs' $tmpfile; then
          echo -e "\n new hang(s) found for $b\n"
        else
          echo "woops: $tmpfile" >&2
          exit 1
        fi

        cat - <<EOF

  reproducer:

  cd ~/findings/$b
  for i in \$(ls ./default/{crashes,hangs}/* 2>/dev/null); do
    time ./*-test \$i
    echo
  done

  or GDB:

  for i in \$(ls ./default/{crashes,hangs}/* 2>/dev/null); do
    gdb -q -batch -ex 'set logging enabled off' -ex 'set pagination off' -ex 'thread apply all bt' -ex 'run' --args ./*-test \$i
    echo
  done

EOF
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
      died=''

      if [[ ! -s $d/fuzz.log ]]; then
        died='no log'

      elif [[ -s $d/default/fuzzer_stats ]]; then
        pid=$(awk '/^fuzzer_pid/ { print $3 }' $d/default/fuzzer_stats)
        if [[ -n $pid ]]; then
          if ! grep -q -w $pid $cgdomain/$(basename $d)/cgroup.procs; then
            died='no cgroup'
          elif ! kill -0 $pid 1>/dev/null; then
            died="pid $pid not running"
          fi
        else
          died='no pid in stats'
        fi
      fi

      if [[ -n $died ]]; then
        echo -e "\n $d is DEAD ($died, pid=$pid)\n"
        if [[ ! -d $fuzzdir/died ]]; then
          mkdir -p $fuzzdir/died
        fi
        if ! sudo $(dirname $0)/fuzz-cgroup.sh $(basename $d); then
          echo -en " cgroup removal $cgdomain failed, killing pids: "
          tac $cgdomain/$(basename $d)/cgroup.procs | tee | xargs -n 1 -r kill -9
          sleep 2
          if ! sudo $(dirname $0)/fuzz-cgroup.sh $(basename $d); then
            echo " cgroup removal failed again: $cgdomain" >&2
            exit 2
          fi
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
    if kill -0 $(<$lck) 2>/dev/null; then
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
    f=$(dirname $d)
    if ! afl-plot $d $f &>/dev/null; then
      echo "no plot for $f"
    fi
  done
}

function repoWasUpdated() {
  cd $1 || exit 1
  if ! git clean -f 1>/dev/null; then
    exit 2
  fi

  local old
  old=$(getCommitId)
  if git pull 1>/dev/null; then
    local new
    new=$(getCommitId)
    [[ $old != "$new" ]]
  else
    return 1
  fi
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

  local fuzz_dirname
  fuzz_dirname=${software}_${fuzzer}_$(date +%Y%m%d-%H%M%S)_$(getCommitId)
  local output_dir=$fuzzdir/$fuzz_dirname
  mkdir -p $output_dir

  cp $exe $output_dir
  # for the reproducer needed
  if [[ $software == "openssl" ]]; then
    cp ${exe}-test $output_dir
  fi

  cd $output_dir
  (
    set -o pipefail

    if [[ $software == "tor" ]]; then
      export AFL_NO_FORKSRV=1
    fi

    export AFL_TMPDIR=$output_dir

    nice -n 3 /usr/bin/afl-fuzz \
      -i $input_dir \
      -o ./ $add \
      -I $(dirname $0)/crash-found.sh \
      -- ./$(basename $exe) |
      ansifilter
  ) &>./fuzz.log &
  local pid_subprozess=$!
  echo -e "$(date)\n    started: $software $fuzzer sub-process $pid_subprozess"

  echo -e "\n$(date)\n    chaining pid $pid_subprozess of $fuzzer"
  sudo $(dirname $0)/fuzz-cgroup.sh $fuzz_dirname $pid_subprozess
}

function stopAFuzzer() {
  local fuzzer=${1?FUZZER IS MISSING}
  local cgroupdir=${2?CGROUP DIR IS MISSING}

  local statfile=$fuzzdir/$fuzzer/default/fuzzer_stats

  echo " stopping fuzzer $fuzzer"

  # stat file not immediately available after start
  if [[ -s $statfile ]]; then
    local pid

    pid=$(awk '/^fuzzer_pid / { print $3 }' $statfile)
    if [[ -n $pid ]]; then
      echo "   pid in fuzzer_stats for $fuzzer: $pid "
      if kill -0 $pid 2>/dev/null; then
        kill -15 $pid
        sleep 10
      else
        echo "   pid $pid is not running"
      fi
    else
      echo "   no pid in statfile: $statfile" >&2
    fi
  else
    echo "   no statfile found: $statfile" >&2
    local pids

    pids=$(<$cgroupdir/cgroup.procs)
    if [[ -n $pids ]]; then
      echo "   kill cgroup tasks of $software $fuzzer: $pids"
      xargs -n 1 kill -15 <<<$pids
      sleep 10
      pids=$(<$cgroupdir/cgroup.procs)
      if [[ -n $pids ]]; then
        echo "   get roughly with $pids"
        xargs -n 1 kill -9 < <(cat $cgroupdir/cgroup.procs)
        sleep 1
      fi
    else
      echo -n "   got no cgrop pid for $cgroupdir"
    fi
  fi

  if ! sudo $(dirname $0)/fuzz-cgroup.sh $fuzzer; then
    echo -e "\n woops ^^"
  fi
  echo
}

function runFuzzers() {
  local wanted=${1?}

  local current
  current=$(ls -d $fuzzdir/${software}_* 2>/dev/null | wc -w)
  local delta
  delta=$((wanted - current))

  if [[ $delta -gt 0 ]]; then
    echo -en "\n$(date)\n job changes: $delta x $software: "

    if [[ $force_build -eq 1 ]] || softwareWasCloned || softwareWasUpdated || ! getFuzzers $software | grep -q '.'; then
      cd ~/sources/$software
      echo -e "\n$(date)\n building $software ...\n"
      AFL_NO_COLOR=1 buildSoftware
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
        stopAFuzzer $fuzzer $d
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

# git log etc
export GIT_PAGER="cat"
export PAGER="cat"

# compile time
export CC="/usr/bin/afl-clang-fast"
export CXX="${CC}++"
export CFLAGS="-O2 -pipe -march=native"
export CXXFLAGS="$CFLAGS"
export MAKEFLAGS="-j 4"
export PERFORMANCE=1
export AFL_QUIET=1

# start of a fuzzer
export AFL_EXIT_WHEN_DONE=1
export AFL_HARDEN=1
export AFL_SKIP_CPUFREQ=1
export AFL_SHUFFLE_QUEUE=1

# run of a fuzzer
export AFL_NO_SYNC=1

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
    echo " sth wrong with $opt $OPTARG" >&2
    exit 1
    ;;
  esac
done
