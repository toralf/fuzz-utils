#!/bin/sh
# set -x


# main entrypoint to start/stop fuzzers and inspect their outcome


# simple lock to avoid being run in parallel
#
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


function cleanUp()  {
  local rc=${1:-$?}
  trap - QUIT TERM EXIT

  rm -f "$lck"
  exit $rc
}


function getGitId() {
  git log --max-count=1 --pretty=format:%H | cut -c1-12
}


function startAFuzzer()  {
  local fuzzer=${1?:name ?!}
  local exe=${2?:exe ?!}
  local idir=${3?:idir ?!}
  shift 3
  local add=${@:-}

  cd ~/$software
  local git_id=$(getGitId)

  local fdir=${software}_${fuzzer}_$(date +%Y%m%d-%H%M%S)_${git_id}
  local odir=/tmp/fuzzing/$fdir
  mkdir -p $odir

  cp $exe $odir
  if [[ $software = "openssl" ]]; then
    cp ${exe}-test $odir
  fi

  cd $odir
  nohup nice -n 1 /usr/bin/afl-fuzz -i $idir -o ./ $add -- ./$(basename $exe) &>./fuzz.log &
  local fuzzer_pid=$!
  echo -e " $software : $fuzzer  $fuzzer_pid"

  if ! sudo $(dirname $0)/fuzz-cgroup.sh $fdir $fuzzer_pid; then
    echo " failed to put $fuzzer_pid into CGroup"
  fi
  echo
}


function runFuzzers() {
  local wanted=$1

  local running=$(ls -d /sys/fs/cgroup/cpu/local/${software}_* 2>/dev/null | wc -w)
  ((diff = $wanted - $running))
  if [[ $diff -gt 0 ]]; then
    echo "starting $diff fuzzer(s) ..."
    getFuzzers |\
    shuf |\
    while read -r fuzzer exe idir add
    do
      if [[ -x $exe && -d $idir ]]; then
        if startAFuzzer $fuzzer $exe $idir $add; then
          if ! ((diff=diff-1)); then
            break
          fi
        else
          echo " something failed with $fuzzer"
        fi
      else
        echo " skipped: $fuzzer $exe $idir $add"
        echo
      fi
    done
  elif [[ $diff -lt 0 ]]; then
    echo "stopping $diff fuzzer(s) ..."
    awk '/^fuzzer_pid / { print $3 }' /tmp/fuzzing/${software}_*/default/fuzzer_stats |\
    while read -r fuzzer_pid
    do
      if kill -0 $fuzzer_pid 2>/dev/null; then
        echo " killing $fuzzer_pid"
        kill -15 $fuzzer_pid
          if ! ((diff=diff+1)); then
            break
          fi
      fi
    done
  fi
}


function plotData() {
  for f in $(ls -d /tmp/fuzzing/${software}_* 2>/dev/null)
  do
    cd $f
    afl-plot ./default ./ &>/dev/null || continue
  done
}



function checkForFindings() {
  ls -l /tmp/fuzzing/${software}_*/default/{crashes,hangs}/* 2>/dev/null
}



function updateRepo(){
  cd $1
  local old=$(getGitId)
  git pull 1>/dev/null
  local new=$(getGitId)
  [[ $old != $new ]]
}


#######################################################################
#
set -eu
export LANG=C.utf8

export CC="/usr/bin/afl-cc"
export CXX="/usr/bin/afl-c++"
export CFLAGS="-O2 -pipe -march=native"
export CXXFLAGS="-O2 -pipe -march=native"

export AFL_EXIT_WHEN_DONE=1
export AFL_HARDEN=1
export AFL_SKIP_CPUFREQ=1

export GIT_PAGER="cat"
export PAGER="cat"

cd ~
software=${1?software is missing}
source $(dirname $0)/fuzz-lib-${software}.sh

lck=/tmp/$(basename $0).${software}.lock
lock
trap cleanUp QUIT TERM EXIT

shift
while getopts bcfpr:u opt
do
  case $opt in
    b)  buildFuzzers ;;
    c)  cloneRepo ;;
    f)  checkForFindings ;;
    p)  plotData ;;
    r)  runFuzzers "$OPTARG" ;;
    u)  if repoWasUpdated; then buildFuzzers; fi ;;
  esac
done

