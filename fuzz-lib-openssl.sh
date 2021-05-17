# specific routines to fuzz OpenSSL


function buildSoftware() {
  cd ~/$software
  make -j $jobs
}


function configureSoftware() {
  cd ~/$software

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
  cd ~
  ls openssl/fuzz/corpora/ |\
  while read -r fuzzer
  do
    exe=~/openssl/fuzz/$fuzzer
    idir=~/openssl/fuzz/corpora/$fuzzer

    if [[ -x $exe && -d $idir ]]; then
      echo $fuzzer $exe $idir
    fi
  done
}


function softwareWasCloned()  {
  if [[ -d ~/$software ]]; then
    return 1
  fi
  cd ~
  git clone https://github.com/openssl/$software.git
}


function softareWasUpdated()  {
  repoWasUpdated ~/$software
}
