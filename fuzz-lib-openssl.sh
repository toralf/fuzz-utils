# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later

# specific routines to fuzz OpenSSL

function buildSoftware() {
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
}

function getFuzzers() {
  local software=${1?}

  ls ~/sources/$software/fuzz/corpora/ |
    while read -r fuzzer; do
      exe=~/sources/$software/fuzz/$fuzzer
      idir=~/sources/$software/fuzz/corpora/$fuzzer

      if [[ -x $exe && -d $idir ]]; then
        # for timeouts see https://github.com/openssl/openssl/issues/25707
        echo $fuzzer $exe $idir -t 100
      fi
    done
}

function softwareWasCloned() {
  cd ~/sources/ || exit 1

  if [[ -d ./$software && -s ./$software/fuzz/corpora/.git ]]; then
    return 1
  fi

  if ! git clone https://github.com/openssl/$software.git; then
    exit 1
  fi

  cd ./$software
  if ! git submodule update --init --recursive fuzz/corpora; then
    exit 1
  fi
}

function softwareWasUpdated() {
  local rc=2

  if repoWasUpdated ~/sources/$software; then
    rc=0
  fi

  cd ~/sources/$software
  if git submodule update --remote --recursive fuzz/corpora | grep -q '.'; then
    rc=0
  fi

  return $rc
}
