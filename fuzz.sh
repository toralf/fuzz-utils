#!/bin/sh
# set -x


# start/stop fuzzers and keep their outcome


function cleanUp()  {
  local rc=${1:-$?}
  trap - QUIT TERM EXIT

  rm -f "$lck"
  exit $rc
}


function getCommitId() {
  git log --max-count=1 --pretty=format:%H | cut -c1-12
}


function keepFindings() {
  find /tmp/fuzzing/ -wholename "*/default/crashes/*" -o -wholename "*/default/hangs/*" |\
  while read f
  do
    sed -e 's,/default/crashes/.*,,g' <<< $f
  done |\
  sort -u |\
  while read d
  do
    rsync -av /tmp/fuzzing/$d ~
  done
}


function lock()  {
  if [[ -s $lck ]]; then
    echo -n " found $lck: "
    cat $lck
    if kill -0 $(cat $lck) 2>/dev/null; then
      echo " valid, exiting ..."
      return 1
    else
      echo " stalled, continuing ..."
    fi
  fi
  echo "$(date) $$" > $lck
}


function plotData() {
  for d in $(ls -d /tmp/fuzzing/* 2>/dev/null)
  do
    afl-plot $d/default $d &>/dev/null || continue
  done
}


function repoWasUpdated() {
  cd $1
  local old=$(getCommitId)
  git pull 1>/dev/null
  local new=$(getCommitId)
  [[ $old != $new ]]
}


function runFuzzers() {
  local wanted=$1
  local running=$(ls -d /sys/fs/cgroup/cpu/local/${software}_* 2>/dev/null | wc -w)

  if ! ((diff = $wanted - $running)); then
    return 0

  elif [[ $diff -gt 0 ]]; then
    if softwareWasCloned || softareWasUpdated; then
      configureSoftware
    fi

    echo " building $software ..."
    buildSoftware

    echo -n "starting $diff $software: "
    # prefer non-running, but at least start $diff
    (
      getFuzzers |\
      while read f
      do
        if ! ls -d /sys/fs/cgroup/cpu/local/${software}_* &>/dev/null; then
          echo $f
        fi
      done |\
      shuf -n $diff
      getFuzzers | shuf -n $diff
    ) |\
    head -n $diff |\
    while read -r line
    do
      startAFuzzer $line
    done

  else
    echo -n "stopping $diff $software: "
    ((diff=-diff))
    ls -d /sys/fs/cgroup/cpu/local/${software}_* 2>/dev/null |\
    shuf -n $diff |\
    while read d
    do
      # stats file is just created after a short while
      statfile=/tmp/fuzzing/$(basename $d)/default/fuzzer_stats
      if [[ -s $statfile ]]; then
        pid=$(awk ' /^fuzzer_pid / { print $3 } ' $statfile)
        echo -n "    stats: $pid"
        kill -15 $pid
      else
        tasks=$(cat $d/tasks)
        echo -n "    cgroup: $tasks"
        kill -15 $tasks
      fi
    done
  fi
  echo
}


function startAFuzzer()  {
  local fuzzer=${1?:name ?!}
  local exe=${2?:exe ?!}
  local idir=${3?:idir ?!}
  shift 3
  local add=${@:-}

  cd ~/$software

  local fdir=${software}_${fuzzer}_$(date +%Y%m%d-%H%M%S)_$(getCommitId)
  local odir=/tmp/fuzzing/$fdir
  mkdir -p $odir

  cp $exe $odir
  # TODO: move this quirk to fuzz-lib-openssl.sh
  if [[ $software = "openssl" ]]; then
    cp ${exe}-test $odir
  fi

  cd $odir
  nice -n 1 /usr/bin/afl-fuzz -i $idir -o ./ $add -- ./$(basename $exe) &> ./fuzz.log &
  sudo $(dirname $0)/fuzz-cgroup.sh $fdir $!
  echo -n "    $fuzzer"
}


#######################################################################
#
set -eu
export LANG=C.utf8

export GIT_PAGER="cat"
export PAGER="cat"

# any change here usually needs a rebuild of $software to take an effect -> run "make clean" in ~/$softwarea manually
export CC="/usr/bin/afl-clang-fast"
export CXX="${CC}++"
export CFLAGS="-O2 -pipe -march=native"
export CXXFLAGS="$CFLAGS"
export AFL_EXIT_WHEN_DONE=1
export AFL_HARDEN=1
export AFL_SKIP_CPUFREQ=1
export AFL_SHUFFLE_QUEUE=1

jobs=8  # parallel make jobs in buildSoftware()

lck=/tmp/$(basename $0).lock
lock
trap cleanUp QUIT TERM EXIT

while getopts fpr:s: opt
do
  case $opt in
    f)  keepFindings
        ;;
    p)  plotData
        ;;
    r)  runFuzzers "$OPTARG"
        ;;
    s)  software="$OPTARG"
        source $(dirname $0)/fuzz-lib-${software}.sh
        ;;
  esac
done

