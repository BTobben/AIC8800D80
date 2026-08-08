#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)

active_sources=(
    src/USB/driver_fw/drivers/aic8800/aic_load_fw
    src/USB/driver_fw/drivers/aic_btusb
    src/USB/driver_fw/drivers/aic_zlp_quirk
)

# Keep new code in the supported USB modules away from unbounded legacy string
# helpers. The wider imported SDK is intentionally outside this build scope.
if git -C "$repo_root" grep -I -n -E \
    '(^|[^[:alnum:]_])(strcpy|strcat|sprintf|vsprintf)[[:space:]]*\(' -- \
    "${active_sources[@]}"; then
    echo "ERROR: unbounded string helper in a supported USB module" >&2
    exit 1
fi

echo 'usb_memory_safety_policy=passed'
