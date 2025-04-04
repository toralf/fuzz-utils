# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later

# specific routines to fuzz Tor

function buildSoftware() {
  rm -f configure Makefile
  ./autogen.sh

  ./configure \
    --disable-libfuzzer --enable-unittests --enable-gcc-hardening --enable-linker-hardening \
    --enable-module-relay --disable-systemd \
    --enable-pic --enable-libscrypt --enable-seccomp --enable-lzma --enable-zstd --disable-html-manual

  make clean
  make micro-revision.i # https://gitlab.torproject.org/tpo/core/tor/-/issues/29520
  nice -n 3 make -j 1 fuzzers
}

function getFuzzers() {
  local software=${1?}

  ls ~/sources/fuzzing-corpora |
    while read -r fuzzer; do
      exe=~/sources/$software/src/test/fuzz/fuzz-$fuzzer
      idir=~/sources/fuzzing-corpora/$fuzzer

      # dictionary
      f=~/sources/$software/src/test/fuzz/dict/$fuzzer
      [[ -s $f ]] && dict="-x $f" || dict=""

      if [[ -x $exe && -d $idir ]]; then
        echo $fuzzer $exe $idir $dict
      fi
    done
}

function softwareWasCloned() {
  cd ~/sources/ || exit 1

  if [[ -d ./fuzzing-corpora && -d ./$software ]]; then
    return 1
  fi

  if [[ ! -d ./$software ]]; then
    if ! git clone https://gitlab.torproject.org/tpo/core/$software.git/; then
      exit 1
    fi
  fi
  if [[ ! -d ./fuzzing-corpora ]]; then
    if ! git clone https://gitlab.torproject.org/tpo/core/fuzzing-corpora.git/; then
      exit 1
    fi
  fi
}

function softwareWasUpdated() {
  local rc=2

  if repoWasUpdated ~/sources/$software; then
    rc=0
  fi
  if repoWasUpdated ~/sources/fuzzing-corpora; then
    rc=0
  fi

  return $rc
}
