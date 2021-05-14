# specific routines to fuzz OpenSSL


function cloneRepo()  {
  cd ~
  git clone https://github.com/openssl/openssl.git
}



function repoWasUpdated() {
  if updateRepo ~/$software; then
    make clean
    return 0
  fi

  return 1
}


function buildFuzzers() {
  cd ~/$software

  local config_options="enable-fuzz-afl no-shared no-module
    -DPEDANTIC enable-tls1_3 enable-weak-ssl-ciphers enable-rc5
    enable-md2 enable-ssl3 enable-ssl3-method enable-nextprotoneg
    enable-ec_nistp_64_gcc_128 -fno-sanitize=alignment
    --debug"

  if ! ./config $config_options; then
    return 3
  fi

  if ! nice make -j8; then
    return 4
  fi
}


function getFuzzers() {
  cd ~
  ls openssl/fuzz/corpora/ |\
  while read -r fuzzer
  do
    exe=~/openssl/fuzz/$fuzzer
    idir=~/openssl/fuzz/corpora/$fuzzer

    echo $fuzzer $exe $idir
  done
}
