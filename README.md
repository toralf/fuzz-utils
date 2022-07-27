[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# fuzz-utils
fuzz Tor, OpenSSL and probably more using [AFL++](https://github.com/AFLplusplus/AFLplusplus/)

Move the bins into */opt/fuzz-utils/*.

Mount `/tmp` at a *tmpfs* to avoid heavy I/O stress to the disk.
Findings will be synced to `$HOME/findings`.

`fuzz.sh` is the entry point, `fuzz-lib-openssl.sh` and `fuzz-lib-tor.sh` provide target specific helper libs.
`simple-http-server.py` can be used to delivers metric files.

crontab example:

```
# start fuzzers + provides AFL plot metrics
@reboot   /opt/fuzz-utils/fuzz.sh -o 2 -t 2; (cd /tmp/fuzzing && nice /opt/fuzz-utils/simple-http-server.py --address x.y.z --port 12345 &>/tmp/web-fuzzing.log &)

# findings, scheduling, plots
@hourly   /opt/fuzz-utils/fuzz.sh -f -o 2 -t 2 -p -f
```

Grant the user (i.e.: *torproject*) these sudo rights:

```
torproject ALL=(ALL) NOPASSWD: /opt/fuzz-utils/fuzz-cgroup.sh
```

