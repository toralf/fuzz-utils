# SPDX-License-Identifier: GPL-3.0-or-later
# specific routines to fuzz Tor

function buildSoftware() {
  cd ~/sources/$software
  make micro-revision.i # https://gitlab.torproject.org/tpo/core/tor/-/issues/29520
  nice -n 3 make -j $jobs fuzzers
}

function configureSoftware() {
  cd ~/sources/$software

  if [[ ! -x ./configure ]]; then
    rm -f Makefile
    ./autogen.sh
  fi

  if [[ ! -f Makefile ]]; then
    # use the configure options from the official Gentoo ebuild
    # but: disable coverage (huge slowdown) + enable zstd-advanced-apis
    local gentoo="
        --prefix=/usr --build=x86_64-pc-linux-gnu --host=x86_64-pc-linux-gnu --mandir=/usr/share/man --infodir=/usr/share/info --datadir=/usr/share --sysconfdir=/etc --localstatedir=/var/lib --disable-dependency-tracking --disable-silent-rules --docdir=/usr/share/doc/tor-9999 --htmldir=/usr/share/doc/tor-9999/html --libdir=/usr/lib64 --localstatedir=/var --enable-system-torrc --disable-android --disable-html-manual --disable-libfuzzer --enable-missing-doc-warnings --disable-module-dirauth --enable-pic --disable-rust --disable-restart-debugging --disable-zstd-advanced-apis --enable-asciidoc --enable-manpage --enable-lzma --enable-libscrypt --enable-seccomp --enable-module-relay --disable-systemd --enable-gcc-hardening --enable-linker-hardening --disable-unittests --disable-coverage --enable-zstd
    "
    local override="
        --enable-module-dirauth --enable-zstd-advanced-apis --enable-unittests --disable-coverage
    "

    ./configure $gentoo $override
  fi
}

function getFuzzers() {
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
  cd ~/sources/

  if [[ -d ./fuzzing-corpora && -d ./$software ]]; then
    return 1
  fi

  if [[ ! -d ./fuzzing-corpora ]]; then
    git clone https://git.torproject.org/fuzzing-corpora.git
  fi
  if [[ ! -d ./$software ]]; then
    git clone https://git.torproject.org/$software.git
  fi
}

function softwareWasUpdated() {
  # bash optimizes in "if [[ A || B ]]" the right term B away if A is false
  # - but we have to call repoWasUpdated() in both directories
  if repoWasUpdated ~/sources/$software; then
    repoWasUpdated ~/sources/fuzzing-corpora || true # neutralize "set -e"
    return 0
  fi
  return 1
}
