[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# fuzz-utils

fuzz testing of Tor and OpenSSL using [AFL++](https://github.com/AFLplusplus/AFLplusplus/)

`fuzz.sh` is the entry point, `fuzz-lib-openssl.sh` and `fuzz-lib-tor.sh` do provide target specific helper libs.

`/tmp/torproject/fuzzing` should be a _tmpfs_ to avoid heavy I/O stress to the disk.
Findings will be synced from there to `$HOME/findings`.
The `fuzz-cgroup.sh` has to be run as root.

Example:

```bash

# (f)indings, 1x (o)penssl, 1x (t)or, (p)lots, (f)indings
*/5 * * * *   /opt/fuzz-utils/fuzz.sh -f -o 1 -t 1 -p -f
```

`simple-http-server.sh` provides a simple Python HTTP server.
