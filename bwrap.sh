#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# example call:
# simple-http-server.sh webuser --address 1.2.3.4 --port 56789 --directory /tmp/www

set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

sandbox=(env -i
  /usr/bin/bwrap
  --clearenv
  --unshare-cgroup
  --unshare-ipc
  --unshare-uts
  --unshare-pid
  --new-session
  --die-with-parent
  --ro-bind / /
  --proc /proc
  --dev /dev
  --ro-bind /sys /sys
)

[[ $# -ne 0 ]]

"${sandbox[@]}" -- ${@}