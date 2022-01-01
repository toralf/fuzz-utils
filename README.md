# fuzz-utils
fuzz Tor, OpenSSL and probably more using [AFL++](https://github.com/AFLplusplus/AFLplusplus/)

`fuzz.sh` is the entry point, `fuzz-lib-openssl.sh` and `fuzz-lib-tor.sh` provide target specific helper libs.
`simple-http-server.py` can be used to delivers metric files.

crontab example:

```
# provides AFL plots of metrics
@reboot /opt/fuzz-utils/fuzz.sh -w <address>:<port> &>/tmp/fuzz-web.log

# start OpenSSL and Tor fuzzers
@reboot /opt/fuzz-utils/fuzz.sh -o 2 -t 2

# # findings, scheduling, plots
@hourly /opt/fuzz-utils/fuzz.sh -f -o 2 -t 2 -p -f
```
Live data are in `/tmp/fuzzing`, findings are synced to `$HOME/findings`.

Mount `/tmp` at a *tmpfs* to avoid heavy I/O stress to the disk.

