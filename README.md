# fuzz-utils
fuzz Tor, OpenSSL and probably more using [AFL++](https://github.com/AFLplusplus/AFLplusplus/)

`fuzz-main.sh` contains the logic, `fuzz-lib-openssl.sh` and `fuzz-lib-tor.sh` are target specific helper libs.
`simple-http-server.py` is a simple helper to watch progres.

Run it via cron, eg.:

```
@reboot mkdir /tmp/fuzzing; cd /tmp/fuzzing && nice /opt/fuzz-utils/simple-http-server.py --port 12345 --address x.y.z &>/tmp/simple-http-server-fuzzing.log

@reboot /opt/fuzz-utils/fuzz.sh -s openssl -r 2 -s tor -r 2
@hourly /opt/fuzz-utils/fuzz.sh -s openssl -r 2 -s tor -r 2

*/5 * * * * /opt/fuzz-utils/fuzz.sh -k -p &>/dev/null

```
Crashes are rsynced to your HOME directory.
Point your browser to http://x.y.z:12345 to see few metrics.
Watch UNIX processes via:

```bash
watch -c "pgrep afl | xargs -n 1 pstree -UlnpuTa"
```


You should mount `/tmp` at a *tmpfs* to avoid heavy I/O to your disks.

