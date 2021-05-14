# fuzz-utils
fuzz Tor, OpenSSL and probably more using https://github.com/AFLplusplus/AFLplusplus/

`fuzz-main.sh` contains the logic, `fuzz-lib-openssl.sh` and `fuzz-lib-tor.sh` are target specific helper libs.
Run it via cron, eg.:

```
@reboot mkdir /tmp/fuzzing; (cd /tmp/fuzzing && nice /opt/fuzz-utils/simple-http-server.py &>/tmp/simple-http-server-fuzzing.log &)

@reboot /opt/fuzz-utils/fuzz-main.sh openssl -u -r 4
@reboot /opt/fuzz-utils/fuzz-main.sh tor     -u -r 4

9 * * * * /opt/fuzz-utils/fuzz-main.sh openssl -f -p -u -r 4
9 * * * * /opt/fuzz-utils/fuzz-main.sh tor     -f -p -u -r 4
```

