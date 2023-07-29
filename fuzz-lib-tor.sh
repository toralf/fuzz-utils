# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# specific routines to fuzz Tor

function buildSoftware() {
  local jobs=${1:-1}

  make clean

  if [[ ! -x ./configure ]]; then
    rm -f Makefile
    ./autogen.sh
  fi

  if [[ ! -f Makefile ]]; then
    # use the configure options from the official Gentoo ebuild
    local gentoo="
      --prefix=/usr --build=x86_64-pc-linux-gnu --host=x86_64-pc-linux-gnu --mandir=/usr/share/man --infodir=/usr/share/info --datadir=/usr/share --sysconfdir=/etc --localstatedir=/var/lib --datarootdir=/usr/share --disable-dependency-tracking --disable-silent-rules --docdir=/usr/share/doc/tor-9999 --htmldir=/usr/share/doc/tor-9999/html --libdir=/usr/lib64 --localstatedir=/var --disable-all-bugs-are-fatal --enable-system-torrc --disable-android --disable-coverage --disable-html-manual --disable-libfuzzer --enable-missing-doc-warnings --disable-module-dirauth --enable-pic --disable-restart-debugging --disable-zstd-advanced-apis --enable-asciidoc --enable-manpage --enable-lzma --enable-libscrypt --enable-seccomp --enable-module-relay --disable-systemd --enable-gcc-hardening --enable-linker-hardening --enable-unittests --enable-zstd
    "
    ./configure $gentoo --enable-module-dirauth
  fi
  make micro-revision.i # https://gitlab.torproject.org/tpo/core/tor/-/issues/29520
  nice -n 3 make -j $jobs fuzzers
}

function getFuzzers() {
  local software=${1?}

  ls ~/sources/fuzzing-corpora |
    while read -r fuzzer; do
      exe=~/sources/$software/src/test/fuzz/fuzz-$fuzzer
      idir=~/sources/fuzzing-corpora/$fuzzer

      # optional: dictionary for the fuzzer
      dict=~/sources/$software/src/test/fuzz/dict/$fuzzer
      [[ -s $dict ]] && add="-x $dict" || add=""

      if [[ -x $exe && -d $idir ]]; then
        echo $fuzzer $exe $idir $add
      fi
    done
}

function softwareWasCloned() {
  if ! cd ~/sources; then
    return 1
  fi

  if [[ -d ./fuzzing-corpora && -d ./$software ]]; then
    return 1
  fi

  if [[ ! -d ./fuzzing-corpora ]]; then
    git clone https://gitlab.torproject.org/tpo/core/fuzzing-corpora.git/
  fi
  if [[ ! -d ./$software ]]; then
    git clone https://gitlab.torproject.org/tpo/core/$software.git/
  fi
}

function softwareWasUpdated() {
  # in "if [[ A || B ]]" bash optimizes B away if A is false
  # - but we have to call repoWasUpdated() in both directories
  if repoWasUpdated ~/sources/$software; then
    repoWasUpdated ~/sources/fuzzing-corpora || true
    return 0
  else
    return 1
  fi
}
