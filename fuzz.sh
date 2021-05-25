#!/bin/sh
# set -x


# start/stop fuzzers, check for findings and plot metrics


function checkForFindings() {
  ls /tmp/fuzzing/ |\
  while read -r d
  do
    txz=~/findings/$d.tar.xz
    options=""
    if [[ -f $txz ]]; then
      options="-newer $txz"
    fi

    find /tmp/fuzzing/$d -wholename "*/default/crashes/*" -o -wholename "*/default/hangs/*" $options |\
    head -n 1 |\
    while read -r dummy
    do
      echo -e "\n new findings in $d"

      rsync -av /tmp/fuzzing/$d ~/findings/
      cd ~/findings/
      chmod -R g+r ./$d
      find ./$d -type d | xargs chmod g+x
      tar -cJpf $txz ./$d
      echo
      ls -lh $txz
      echo
    done
  done

  for i in $(ls /tmp/fuzzing/*/fuzz.log 2>/dev/null)
  do
    tail -n 15 $i |\
    colourStrip |\
    grep -B 15 -A 15 -e 'PROGRAM ABORT' -e 'Testing aborted' && echo || true
  done

  return 0
}


function cleanUp()  {
  local rc=${1:-$?}
  trap - QUIT TERM EXIT

  rm -f "$lck"
  exit $rc
}


function colourStrip()  {
  if [[ -x /usr/bin/ansifilter ]]; then
    ansifilter
  else
    cat
  fi
}


function getCommitId() {
  git log --max-count=1 --pretty=format:%H | cut -c1-12
}


function lock()  {
  if [[ -s $lck ]]; then
    echo -n " found lock file $lck: "
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
    if softwareWasCloned || softwareWasUpdated; then
      configureSoftware
      # make clean  # needed after an update of AFL++
    fi
    echo
    echo " building $software ..."
    buildSoftware
    echo -n "starting $diff $software: "
    throwFuzzers $diff |\
    while read -r line
    do
      startAFuzzer $line
    done

  else
    ((diff=-diff))
    echo -n "stopping $diff $software: "
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

  cd ~/sources/$software

  local fdir=${software}_${fuzzer}_$(date +%Y%m%d-%H%M%S)_$(getCommitId)
  local odir=/tmp/fuzzing/$fdir
  mkdir -p $odir

  cp $exe $odir
  # TODO: move this quirk to fuzz-lib-openssl.sh
  if [[ $software = "openssl" ]]; then
    cp ${exe}-test $odir
  fi

  cd $odir
  nice -n 1 /usr/bin/afl-fuzz -i $idir -o ./ $add -I $0 -- ./$(basename $exe) &> ./fuzz.log &
  sudo $(dirname $0)/fuzz-cgroup.sh $fdir $!
  echo -n "    $fuzzer"
}


function throwFuzzers()  {
  local n=$1
  (
    # prefer non-running, but at least return $n
    getFuzzers |\
    while read f
    do
      if ! ls -d /sys/fs/cgroup/cpu/local/${f}_* &>/dev/null; then
        echo $f
      fi
    done |\
    shuf

    getFuzzers | shuf
  ) |\
  head -n $n
}


#######################################################################
#
set -eu
export LANG=C.utf8

export GIT_PAGER="cat"
export PAGER="cat"

# any change here usually needs a rebuild of $software to take effect -> run "make clean" before !
export CC="/usr/bin/afl-clang-fast"
export CXX="${CC}++"
export CFLAGS="-O2 -pipe -march=native"
export CXXFLAGS="$CFLAGS"

# these affect only the start of a fuzzer
export AFL_EXIT_WHEN_DONE=1
export AFL_HARDEN=1
export AFL_SKIP_CPUFREQ=1
export AFL_SHUFFLE_QUEUE=1

jobs=4  # parallel make jobs in buildSoftware()

lck=/tmp/$(basename $0).lock
lock
trap cleanUp QUIT TERM EXIT

if [[ $# -eq 0 ]]; then
  # this matches "afl-fuzz -I $0"
  checkForFindings
else
  while getopts fo:pt: opt
  do
    case $opt in
      f)  checkForFindings
          ;;
      o)  software="openssl"
          source $(dirname $0)/fuzz-lib-${software}.sh
          runFuzzers "$OPTARG"
          ;;
      p)  plotData
          ;;
      t)  software="tor"
          source $(dirname $0)/fuzz-lib-${software}.sh
          runFuzzers "$OPTARG"
          ;;
    esac
  done
fi
