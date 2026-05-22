#!/usr/bin/env bash
set -euo pipefail

TARGET=x86
source "$(dirname "$0")/lib.sh"

UPDATE_ONLY=false
[[ "${1:-}" == "--update-only" ]] && UPDATE_ONLY=true

update_source
prepare_worktree  "$TARGET"
fetch_feeds       "$TARGET"

if $UPDATE_ONLY; then
    msg "x86 update done"
    exit 0
fi

confirm_continue_build "$TARGET" || exit 0

apply_patches     "$TARGET"
install_feeds
load_config       "$TARGET"
download_sources
build_firmware
collect_output    "$TARGET"

msg "x86 build done"
