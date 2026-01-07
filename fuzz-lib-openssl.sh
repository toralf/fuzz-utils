# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later

# specific routines to fuzz OpenSSL

function buildSoftware() {
  # fuzz/README.md, take configs from Gentoo
  CC=afl-clang-fast ./config \
    enable-camellia enable-ec enable-ec2m enable-sm2 enable-srp enable-idea enable-mdc2 enable-rc5 \
    enable-quic enable-asm no-ktls no-rfc3779 no-sctp no-zlib no-weak-ssl-ciphers \
    --debug

  make clean
  MAKEFLAGS="--jobserver-auth=fifo:/dev/steve" nice -n 3 make
}

function getFuzzers() {
  local software=${1?}

  ls ~/sources/$software/fuzz/corpora/ |
    while read -r fuzzer; do
      exe=~/sources/$software/fuzz/$fuzzer
      idir=~/sources/$software/fuzz/corpora/$fuzzer

      if [[ -x $exe && -d $idir ]]; then
        echo $fuzzer $exe $idir -t 7 # https://github.com/openssl/openssl/issues/25707
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
