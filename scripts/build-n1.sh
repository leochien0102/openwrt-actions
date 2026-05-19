#!/usr/bin/env bash
set -euo pipefail

TARGET=armvirt
source "$(dirname "$0")/lib.sh"

UPDATE_ONLY=false
[[ "${1:-}" == "--update-only" ]] && UPDATE_ONLY=true

update_packit

if $UPDATE_ONLY; then
    msg "N1 update done"
    exit 0
fi

stage_rootfs      "$TARGET"
run_packit        "mk_s905d_n1.sh"
compress_firmware "$TARGET"

msg "N1 packit done"
