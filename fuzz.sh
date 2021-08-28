#!/bin/sh
# set -x


# start/stop fuzzers, check for findings and plot metrics


function checkForFindings() {
  ls -d $fuzzdir/*_*_*-*_* 2>/dev/null |\
  while read -r d
  do
    b=$(basename $d)
    txz=~/findings/$b.tar.xz
    options=""
    if [[ -f $txz ]]; then
      options="-newer $txz"
    fi

    result=$fuzzdir/result
    find $d -wholename "*/default/crashes/*" -o -wholename "*/default/hangs/*" $options > $result
    if [[ -s $result ]]; then
      if grep -q "crashes" $result; then
        echo " new CRASHES in $d"
      else
        echo " new hangs in $d"
      fi

      rsync -archive --delete --quiet $d ~/findings/
      cd ~/findings/
      chmod -R g+r ./$b
      find ./$b -type d -exec chmod g+x {} +
      tar -cJpf $txz ./$b
      ls -lh $txz
      echo
    fi
    rm $result
  done

  for i in $(ls $fuzzdir/*/fuzz.log 2>/dev/null)
  do
    if tail -v -n 10 $i | colourStrip | grep -B 10 -A 10 -e 'PROGRAM ABORT' -e 'Testing aborted'; then
      [[ -d $fuzzdir/aborted/ ]] || mkdir -p $fuzzdir/aborted/
      d=$(dirname $i)
      mv $d $fuzzdir/aborted/
    fi
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
  echo "$(date) $$" > $lck || exit 1
}


function plotData() {
  for d in $(ls -d $fuzzdir/* 2>/dev/null)
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
      echo
      echo " configuring $software ..."
      configureSoftware
      make clean
    fi
    echo
    echo " building $software ..."
    buildSoftware

    echo -en "\nstarting $diff $software: "
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
    while read -r d
    do
      # file is not immediately available
      fuzzer=$(basename $d)
      statfile=$fuzzdir/$fuzzer/default/fuzzer_stats
      if [[ -s $statfile ]]; then
        pid=$(awk ' /^fuzzer_pid / { print $3 } ' $statfile)
        echo -n "    stats ($fuzzer): $pid"
        kill -15 $pid
      else
        tasks=$(cat $d/tasks)
        echo -n "    cgroup ($fuzzer): $tasks"
        kill -15 $tasks
      fi
    done
  fi
  echo
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
  local odir=$fuzzdir/$fdir
  mkdir -p $odir

  cp $exe $odir
  # TODO: move this quirk to fuzz-lib-openssl.sh ?
  if [[ $software = "openssl" ]]; then
    cp ${exe}-test $odir
  fi

  cd $odir
  # nice makes sysstat graphs better readable
  # "setsid -w" causes the autogroup scheduler (if used) to create a new group
  nice -n 3 setsid -w /usr/bin/afl-fuzz -i $idir -o ./ $add -I $0 -- ./$(basename $exe) &> ./fuzz.log &
  sudo $(dirname $0)/fuzz-cgroup.sh $fdir $!
  echo -n "    $fuzzer"
}


function throwFuzzers()  {
  local n=$1

  # prefer a non-running + non-aborted (best) over a non-running aborted (good), or choose at least one (ok)
  truncate -s 0 $fuzzdir/next.{best,good,ok}

  while read -r f
  do
    read -r exe idir add <<< $f
    if ! ls -d /sys/fs/cgroup/cpu/local/${software}_${exe}_* &>/dev/null; then
      if ! ls -d  $fuzzdir/aborted/${software}_${exe}_* &>/dev/null; then
        echo "$exe $idir $add" >> $fuzzdir/next.best
      else
        echo "$exe $idir $add" >> $fuzzdir/next.good
      fi
    else
      echo "$exe $idir $add" >> $fuzzdir/next.ok
    fi
  done < <(getFuzzers | shuf)

  (
    cat $fuzzdir/next.best
    cat $fuzzdir/next.good
    cat $fuzzdir/next.ok
  ) |\
  head -n $n
  rm $fuzzdir/next.{best,good,ok}
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

jobs=8                      # parallel make jobs in buildSoftware()
fuzzdir="/tmp/fuzzing"
if [[ ! -d $fuzzdir ]]; then
  mkdir $fuzzdir

  cat << EOF > $fuzzdir/robots.txt
User-agent: *
Disallow: /

EOF
fi

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
