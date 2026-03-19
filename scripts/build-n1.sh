#!/usr/bin/env bash
set -euo pipefail

TARGET=armvirt
source "$(dirname "$0")/lib.sh"

update_packit
stage_rootfs      "$TARGET"
run_packit        "mk_s905d_n1.sh"
compress_firmware "$TARGET"

msg "N1 packit done"
