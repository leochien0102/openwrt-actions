#!/usr/bin/env bash
set -euo pipefail

TARGET=armvirt
source "$(dirname "$0")/lib.sh"

UPDATE_ONLY=false
[[ "${1:-}" == "--update-only" ]] && UPDATE_ONLY=true

update_source
prepare_worktree  "$TARGET"
fetch_feeds       "$TARGET"

if $UPDATE_ONLY; then
    msg "Armvirt update done"
    exit 0
fi

apply_patches     "$TARGET"
install_feeds
load_config       "$TARGET"
download_sources
build_firmware

msg "Armvirt build done"
