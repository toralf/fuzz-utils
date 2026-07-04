#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# hook is called by afl++ if a crash was detected

if ! $(dirname $0)/fuzz.sh -f; then
  logger "$0 had an issue"
fi

exit 0
