# fuzz-utils
fuzz Tor, OpenSSL and probably more using [AFL++](https://github.com/AFLplusplus/AFLplusplus/)

`fuzz.sh` is the entry point, `fuzz-lib-openssl.sh` and `fuzz-lib-tor.sh` provide target specific helper libs.
`simple-http-server.py` can be used to delivers metric files.

Run it via cron, eg.:

```
# provides http://x.y.z:12345 for AFL metrics data.
@reboot mkdir /tmp/fuzzing; cd /tmp/fuzzing && nice /opt/fuzz-utils/simple-http-server.py --port 12345 --address x.y.z &>/tmp/simple-http-server-fuzzing.log

@reboot /opt/fuzz-utils/fuzz.sh -s openssl -r 2 -s tor -r 2
@hourly /opt/fuzz-utils/fuzz.sh -s openssl -r 2 -s tor -r 2

*/5 * * * * /opt/fuzz-utils/fuzz.sh -f -p &>/dev/null

```
Crashes are rsynced to the crontab users HOME directory.
Watch UNIX processes via:

```bash
watch -c "pgrep afl | xargs -n 1 pstree -UlnpuTa"
```

You should mount `/tmp` at a *tmpfs* to avoid heavy I/O stress at your disks.

