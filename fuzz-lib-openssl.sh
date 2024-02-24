# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# specific routines to fuzz OpenSSL

function buildSoftware() {
  local jobs=${1:-1}

  # fuzz/README.md
  CC=afl-clang-fast ./config enable-fuzz-afl no-shared no-module \
    -DPEDANTIC enable-tls1_3 enable-weak-ssl-ciphers enable-rc5 \
    enable-md2 enable-ssl3 enable-ssl3-method enable-nextprotoneg \
    enable-ec_nistp_64_gcc_128 -fno-sanitize=alignment \
    --debug
  make clean
  nice -n 3 make -j $jobs
}

function getFuzzers() {
  local software=${1?}

  ls ~/sources/$software/fuzz/corpora/ |
    while read -r fuzzer; do
      exe=~/sources/$software/fuzz/$fuzzer
      idir=~/sources/$software/fuzz/corpora/$fuzzer

      add=""
      case $fuzzer in
      asn1) add="-t 5" ;;
      bignum) continue ;; # https://github.com/openssl/openssl/issues/15356
      decode) add="-t 10" ;;
      esac

      if [[ -x $exe && -d $idir ]]; then
        echo $fuzzer $exe $idir $add
      fi
    done
}

function softwareWasCloned() {
  if ! cd ~/sources/; then
    return 1
  fi

  if [[ -d ./$software && -s ./$software/fuzz/corpora/.git ]]; then
    return 1
  fi

  git clone https://github.com/openssl/$software.git
  cd ./$software
  git submodule update --init --recursive fuzz/corpora
}

function softwareWasUpdated() {
  if ! cd ~/sources/$software; then
    return 1
  fi
  git submodule update --remote --recursive fuzz/corpora
  repoWasUpdated ~/sources/$software
}
