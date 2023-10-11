[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# fuzz-utils

fuzz testing of Tor and OpenSSL using [AFL++](https://github.com/AFLplusplus/AFLplusplus/)

`fuzz.sh` is the entry point.
`fuzz-*.sh` do provide target specific functionality and cgroup handling.

The directory `/tmp/torproject/fuzzing` is used as output.
Findings will be synced from there to `$HOME/findings`.
It should be a _tmpfs_ to avoid heavy I/O stress to the disk.

The `fuzz-cgroup.sh` needs root permissions.
Therefore tweak your local sudoers.d file.

Example:

```bash

# (f)indings, 1x (o)penssl, 1x (t)or, (p)lots, (f)indings
*/5 * * * *   /opt/fuzz-utils/fuzz.sh -f -o 1 -t 1 -p -f
```

`simple-http-server.sh` provides a simple Python HTTP server.
A separate sandbox is provided by `bwrap.sh` which uses [bubblewrap](https://github.com/containers/bubblewrap/), e.g.:

```bash
./bwrap.sh ./simple-http-server.py --address 1.2.3.4 --port 56789 --directory /tmp/www
```

Each sandbox invocation needs 2 or more namespace entries, so tweak the sysctl value _user.max_user_namespaces_ accordingly.
