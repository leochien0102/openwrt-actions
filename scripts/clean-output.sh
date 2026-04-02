#!/usr/bin/env bash
set -euo pipefail

# Usage: clean-output.sh [keep] [target]
#   keep   - number of latest builds to keep per target (default: 3)
#   target - specific target to clean (default: all)
#
# Examples:
#   clean-output.sh          # keep latest 3 builds for all targets
#   clean-output.sh 5        # keep latest 5 builds for all targets
#   clean-output.sh 2 x86    # keep latest 2 builds for x86 only

KEEP="${1:-3}"
FILTER_TARGET="${2:-}"

source "$(dirname "$0")/lib.sh"

clean_firmware() {
    local target="$1"
    local firmware_dir="$OUTPUT_DIR/$target/firmware"

    [[ -d "$firmware_dir" ]] || return 0

    local count
    count=$(ls "$firmware_dir" 2>/dev/null | wc -l)

    if [[ "$count" -le "$KEEP" ]]; then
        msg "$target/firmware: $count file(s), nothing to clean (keep=$KEEP)"
        return 0
    fi

    msg "$target/firmware: $count file(s), keeping latest $KEEP"
    ls -t "$firmware_dir" | tail -n +"$((KEEP + 1))" | while read -r f; do
        msg "  Removing: $f"
        rm -f "$firmware_dir/$f"
    done
}

if [[ -n "$FILTER_TARGET" ]]; then
    clean_firmware "$FILTER_TARGET"
else
    for target_dir in "$OUTPUT_DIR"/*/; do
        target=$(basename "$target_dir")
        clean_firmware "$target"
    done
fi

msg "Done"