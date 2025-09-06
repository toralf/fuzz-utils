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

Example for a cronjob:

```bash
$ crontab -l
# crontab torproject
MAILTO=<snip>

@reboot     sleep 10; ~/start.sh

# (a)bort (f)inding (o)penssl (p)lot (t)or
*/5 * * * * f=/tmp/fuzz.$(date +\%s).$$.log; for s in o t; do /opt/fuzz-utils/fuzz.sh -p -f -$s 1 &>$f; [[ -s $f ]] && cat $f; done; rm $f; sleep 20; /opt/fuzz-utils/fuzz.sh -a
```

Example for a startup file:

```bash
#!/bin/bash
# set -x

set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

mkdir -p /tmp/torproject/fuzzing
echo '<html><h1>Hello World.</h1></html>' >/tmp/torproject/index.html
echo -e "User-agent: *\nDisallow: /\n" >/tmp/torproject/robots.txt

nice /opt/fuzz-utils/bwrap.sh /opt/fuzz-utils/simple-http-server.py --address 65.21.94.49 --port 12345 --directory /tmp/torproject/ &>/tmp/web-fuzz.log &

# fuzzers are started via cron
```

Each sandbox invocation needs 2 or more namespace entries, so set the sysctl value _user.max_user_namespaces_ not below 2.
