#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# triggered by afl-fuzz if a crash was found

$(dirname $0)/fuzz.sh -a
