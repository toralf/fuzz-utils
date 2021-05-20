# specific routines to fuzz OpenSSL


function buildSoftware() {
  cd ~/sources/$software
  make -j $jobs
}


function configureSoftware() {
  cd ~/sources/$software

  local options="enable-fuzz-afl no-shared no-module
    -DPEDANTIC enable-tls1_3 enable-weak-ssl-ciphers enable-rc5
    enable-md2 enable-ssl3 enable-ssl3-method enable-nextprotoneg
    enable-ec_nistp_64_gcc_128 -fno-sanitize=alignment
    --debug
    enable-ubsan"

  ./config $options
  make clean
}


function getFuzzers() {
  cd ~/sources
  ls openssl/fuzz/corpora/ |\
  while read -r fuzzer
  do
    exe=~/sources/openssl/fuzz/$fuzzer
    idir=~/sources/openssl/fuzz/corpora/$fuzzer

    if [[ -x $exe && -d $idir ]]; then
      echo $fuzzer $exe $idir
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


function softareWasUpdated()  {
  repoWasUpdated ~/sources/$software
}
