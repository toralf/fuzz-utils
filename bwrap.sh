#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# user.max_user_namespaces must be greater than zero
# example call:
# bwrap.sh simple-http-server.py --address 1.2.3.4 --port 56789 --directory /tmp/www
# https://github.com/containers/bubblewrap

set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

sandbox=(env -i
  /usr/bin/bwrap
  --clearenv
  --level-prefix
  --unshare-all
  --share-net
  --new-session
  --ro-bind / /
  --dev /dev
  --dev-bind /dev/console /dev/console
  --mqueue /dev/mqueue
  --perms 1777 --tmpfs /dev/shm
  --proc /proc
  --tmpfs /run
  --ro-bind /sys /sys
)

exec "${sandbox[@]}" -- "${@}"
