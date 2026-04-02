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

    # Extract unique timestamps from filenames (first 10 chars)
    local timestamps
    mapfile -t timestamps < <(
        ls "$firmware_dir" 2>/dev/null \
        | grep -oE '^[0-9]{10}' \
        | sort -u -r
    )

    local total="${#timestamps[@]}"

    if [[ "$total" -le "$KEEP" ]]; then
        msg "$target/firmware: $total build(s), nothing to clean (keep=$KEEP)"
        return 0
    fi

    msg "$target/firmware: $total build(s), keeping latest $KEEP"
    local to_remove=("${timestamps[@]:$KEEP}")
    for ts in "${to_remove[@]}"; do
        find "$firmware_dir" -name "${ts}-*" | while read -r f; do
            msg "  Removing: $(basename "$f")"
            rm -f "$f"
        done
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