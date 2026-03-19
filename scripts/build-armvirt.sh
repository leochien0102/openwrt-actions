#!/usr/bin/env bash
set -euo pipefail

TARGET=armvirt
source "$(dirname "$0")/lib.sh"

update_source
prepare_worktree  "$TARGET"
apply_patches     "$TARGET"
update_feeds      "$TARGET"
load_config       "$TARGET"
download_sources
build_firmware

msg "Armvirt build done"
