# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# specific routines to fuzz Tor

function buildSoftware() {
  make clean

  if [[ ! -x ./configure ]]; then
    rm -f Makefile
    ./autogen.sh
  fi

  if [[ ! -f Makefile ]]; then
    # use the configure options from the official Gentoo ebuild
    local gentoo="
      --prefix=/usr --build=x86_64-pc-linux-gnu --host=x86_64-pc-linux-gnu --mandir=/usr/share/man --infodir=/usr/share/info --datadir=/usr/share --sysconfdir=/etc --localstatedir=/var/lib --datarootdir=/usr/share --disable-dependency-tracking --disable-silent-rules --docdir=/usr/share/doc/tor-9999 --htmldir=/usr/share/doc/tor-9999/html --libdir=/usr/lib64 --localstatedir=/var --disable-all-bugs-are-fatal --enable-system-torrc --disable-android --disable-coverage --disable-html-manual --disable-libfuzzer --enable-missing-doc-warnings --disable-module-dirauth --enable-pic --disable-restart-debugging --enable-gpl --enable-module-pow --enable-asciidoc --enable-manpage --enable-lzma --enable-libscrypt --enable-seccomp --enable-module-relay --disable-systemd --enable-gcc-hardening --enable-linker-hardening --disable-unittests --enable-zstd
    "
    ./configure $gentoo --enable-module-dirauth
  fi
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
