[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# fuzz-utils

fuzz testing Tor, OpenSSL et. al using [AFL++](https://github.com/AFLplusplus/AFLplusplus/)

`fuzz.sh` is the entry point, `fuzz-lib-openssl.sh` and `fuzz-lib-tor.sh` provide target specific helper libs.

`/tmp` should be a _tmpfs_ to avoid heavy I/O stress to the disk.
Findings will be synced from there to `$HOME/findings`.
The `fuzz-cgroup.sh` has to be run as root.

`simple-http-server.py` can be used to access metrics over HTTP.

crontab example:

```crontab
@reboot   /opt/fuzz-utils/fuzz.sh -o 2 -t 2; (cd /tmp/fuzzing && nice /opt/fuzz-utils/simple-http-server.py --address x.y.z --port 12345 &>/tmp/web-fuzzing.log &)

# findings, scheduling, plots
@hourly   /opt/fuzz-utils/fuzz.sh -f -o 2 -t 2 -p -f
```
