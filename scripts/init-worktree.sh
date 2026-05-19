#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?Usage: init-worktree.sh <target>  (e.g. rockchip, armvirt, x86)}"
source "$(dirname "$0")/lib.sh"

update_source
prepare_worktree  "$TARGET"
apply_patches     "$TARGET"
update_feeds      "$TARGET"
load_config       "$TARGET"

msg "Worktree for '$TARGET' initialized — run 'make menuconfig' in build/$TARGET to customize"
