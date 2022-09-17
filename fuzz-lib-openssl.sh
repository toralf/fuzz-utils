# SPDX-License-Identifier: GPL-3.0-or-later
# specific routines to fuzz OpenSSL


function buildSoftware() {
  cd ~/sources/$software
  nice -n 3 make -j $jobs
}


function configureSoftware() {
  cd ~/sources/$software

  # https://github.com/openssl/openssl/tree/master/fuzz
  local options="enable-fuzz-afl no-shared no-module
    -DPEDANTIC enable-tls1_3 enable-weak-ssl-ciphers enable-rc5
    enable-md2 enable-ssl3 enable-ssl3-method enable-nextprotoneg
    enable-ec_nistp_64_gcc_128 -fno-sanitize=alignment
    --debug"

  ./config $options
}


function getFuzzers() {
  ls ~/sources/openssl/fuzz/corpora/ |
  while read -r fuzzer
  do
    exe=~/sources/openssl/fuzz/$fuzzer
    idir=~/sources/openssl/fuzz/corpora/$fuzzer

    add=""
    case $fuzzer in
      asn1)   add="-t   +25"  ;;
      bignum) continue        ;;
    esac

    if [[ -x $exe && -d $idir ]]; then
      echo $fuzzer $exe $idir $add
    fi
  done
}


function softwareWasCloned()  {
  cd ~/sources/
  if [[ -d ./$software ]]; then
    return 1
  fi

  git clone https://github.com/openssl/$software.git
}


function softwareWasUpdated()  {
  repoWasUpdated ~/sources/$software
}
