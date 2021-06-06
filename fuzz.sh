#!/bin/sh
# set -x


# start/stop fuzzers, check for findings and plot metrics


function checkForFindings() {
  ls $maindir/ |\
  while read -r d
  do
    txz=~/findings/$d.tar.xz
    options=""
    if [[ -f $txz ]]; then
      options="-newer $txz"
    fi

    findings=$maindir/findings
    find $maindir/$d -wholename "*/default/crashes/*" -o -wholename "*/default/hangs/*" $options > $findings
    if [[ -s $findings ]]; then
      if grep -q "crashes" $findings; then
        echo " new CRASHES in $d"
      else
        echo " new hangs in $d"
      fi

      rsync -archive --delete --quiet $maindir/$d ~/findings/
      cd ~/findings/
      chmod -R g+r ./$d
      find ./$d -type d | xargs chmod g+x
      tar -cJpf $txz ./$d
      ls -lh $txz
      echo
    fi
    rm $findings
  done

  for i in $(ls $maindir/*/fuzz.log 2>/dev/null)
  do
    tail -v -n 15 $i |\
    colourStrip |\
    grep -B 20 -A 5 -e 'PROGRAM ABORT' -e 'Testing aborted' && echo || true
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
  for d in $(ls -d $maindir/* 2>/dev/null)
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
      statfile=$maindir/$(basename $d)/default/fuzzer_stats
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
  local odir=$maindir/$fdir
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

  # prefer a non-running + non-finished
  truncate -s0 $maindir/next.{best,good,ok}

  while read f
  do
    read -r exe dummy <<< $f
    if ! ls -d /sys/fs/cgroup/cpu/local/${exe}_* &>/dev/null; then
      if ! ls -d  $maindir/${exe}_* &>/dev/null; then
       echo "$f" >> $maindir/next.best
      else
        echo "$f" >> $maindir/next.good
      fi
    else
      echo "$f" >> $maindir/next.ok
    fi
  done < <(getFuzzers | shuf)

  cat $maindir/next.{best,good,ok} | head -n $n
  rm $maindir/next.{best,good,ok}
}


function startWebserver()  {
  read -r address port < <(tr ':' ' ' <<< $1)
  cd $maindir && nice $(dirname $0)/simple-http-server.py --address $address --port $port &
}


#######################################################################
#
set -eu
export LANG=C.utf8

export GIT_PAGER="cat"
export PAGER="cat"

# any change here needs a rebuild of $software
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

jobs=4  # parallel make jobs in buildSoftware()
maindir="/tmp/fuzzing"
[[ -d $maindir ]] || mkdir $maindir

lck=/tmp/$(basename $0).lock
lock
trap cleanUp QUIT TERM EXIT

if [[ $# -eq 0 ]]; then
  # this matches "afl-fuzz -I $0"
  checkForFindings
else
  while getopts fo:pt:w: opt
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
      w)  startWebserver "$OPTARG"
          ;;
    esac
  done
fi
