#!/bin/bash
# set -x

# repro for https://github.com/AFLplusplus/AFLplusplus/issues/2761

export GIT_PAGER="cat"
export PAGER="cat"

export CC="/usr/bin/afl-clang-fast"
export CXX="${CC}++"
export CFLAGS="-O2 -pipe -march=native"
export CXXFLAGS="$CFLAGS"
export MAKEFLAGS="-j 24"
export PERFORMANCE=1
export AFL_QUIET=1
export LDFLAGS="-fuse-ld=lld"

# affects the start of a fuzzer
export AFL_EXIT_WHEN_DONE=1
export AFL_HARDEN=1
export AFL_SKIP_CPUFREQ=1
export AFL_SHUFFLE_QUEUE=1

# affects the run of a fuzzer
export AFL_NO_SYNC=1

cd /tmp

if [[ $1 == "openssl" ]]; then
  if [[ ! -d ./openssl ]]; then
    (
      git clone https://github.com/openssl/openssl.git
      cd ./openssl
      git submodule update --init --recursive fuzz/corpora
    )
  fi

  cd ./openssl

  if true; then
    # https://github.com/openssl/openssl/blob/master/fuzz/README.md
    ./config enable-fuzz-afl no-shared no-module \
      -DPEDANTIC enable-tls1_3 enable-weak-ssl-ciphers enable-rc5 \
      enable-md2 enable-nextprotoneg enable-ec_nistp_64_gcc_128 \
      -fno-sanitize=alignment --debug

    make clean
    ls -d fuzz/corpora/* |
      while read -r fc; do
        f=./fuzz/$(basename $fc)
        if [[ -x $f ]]; then
          rm -f $f{,-test}
        fi
      done
    nice -n 3 make $MAKEFLAGS
  fi

  afl-fuzz -i ./fuzz/corpora/cms -o ./ -- ./fuzz/cms

elif [[ $1 == "tor" ]]; then
  if [[ ! -d ./tor ]]; then
    git clone https://gitlab.torproject.org/tpo/core/tor.git
  fi
  if [[ ! -d ./fuzzing-corpora ]]; then
    git clone https://gitlab.torproject.org/tpo/core/fuzzing-corpora.git
  fi

  cd ./tor

  if true; then
    ./autogen.sh

    ./configure \
      --prefix=/usr \
      --mandir=/usr/share/man --infodir=/usr/share/info --datadir=/usr/share --sysconfdir=/etc \
      --localstatedir=/var --datarootdir=/usr/share \
      --disable-dependency-tracking --disable-silent-rules --disable-all-bugs-are-fatal --enable-system-torrc \
      --disable-android --disable-coverage --disable-html-manual --disable-libfuzzer --enable-missing-doc-warnings \
      --disable-module-dirauth --enable-pic --disable-restart-debugging --enable-gpl --enable-module-pow \
      --enable-gcc-hardening --enable-linker-hardening \
      --enable-libscrypt --enable-seccomp --enable-module-relay --enable-zstd \
      --enable-unittests --disable-asciidoc --disable-manpage --disable-lzma

    make clean
    make micro-revision.i # https://gitlab.torproject.org/tpo/core/tor/-/issues/29520
    nice -n 3 make $MAKEFLAGS fuzzers
  fi

  #afl-fuzz -i ../fuzzing-corpora/diff-apply -o ./ -- ./src/test/fuzz/fuzz-diff-apply
  afl-fuzz -i ../fuzzing-corpora/diff-apply -o ./ -- ./src/test/fuzz/fuzz-consensus
fi
