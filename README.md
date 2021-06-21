# fuzz-utils
fuzz Tor, OpenSSL and probably more using [AFL++](https://github.com/AFLplusplus/AFLplusplus/)

`fuzz.sh` is the entry point, `fuzz-lib-openssl.sh` and `fuzz-lib-tor.sh` provide target specific helper libs.
`simple-http-server.py` can be used to delivers metric files.

crontab example:

```
# provides http://x.y.z:12345 for AFL plots of metrics
@reboot /opt/fuzz-utils/fuzz.sh -w <address>:<port> &>/tmp/fuzz-web.log

# start 4 OpenSSL and 4 Tor fuzzers
@reboot /opt/fuzz-utils/fuzz.sh -o 4 -t 4

# restart if needed to keep 4 OpenSSL and 4 Tor fuzzers running, look for findings and create plots
@hourly /opt/fuzz-utils/fuzz.sh -f -o 4 -t 4 -p
```
Live data are in `/tmp/fuzzing`, findings are synced to `$HOME/findings`.

Mount `/tmp` at a *tmpfs* to avoid heavy I/O stress to the disk.

