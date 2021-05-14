# specific routines to fuzz Tor


function cloneRepo()  {
  cd ~
  git clone https://git.torproject.org/fuzzing-corpora.git
  git clone https://git.torproject.org/tor.git
}


function repoWasUpdated() {
  if updateRepo ~/fuzzing-corpora || updateRepo ~/$software; then
    make clean
    return 0
  fi

  return 1
}


function buildFuzzers() {
  cd ~/$software

  if [[ ! -x ./configure ]]; then
    rm -f Makefile
    if ! ./autogen.sh 2>&1; then
      return 2
    fi
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
    if ! ./configure $gentoo $override; then
      return 3
    fi
  fi

  # https://trac.torproject.org/projects/tor/ticket/29520
  if ! make micro-revision.i 2>&1; then
    return 4
  fi

  if ! nice make -j8 fuzzers 2>&1; then
    return 5
  fi
  echo
}


function getFuzzers() {
  cd ~
  ls fuzzing-corpora |\
  while read -r fuzzer
  do
    exe=~/$software/src/test/fuzz/fuzz-$fuzzer
    idir=~/fuzzing-corpora/$fuzzer

    # optional: dictionary for the fuzzer
    dict=~/$software/src/test/fuzz/dict/$fuzzer
    [[ -s $dict ]] && add="-x $dict" || add=""

    echo $fuzzer $exe $idir $add
  done
}
