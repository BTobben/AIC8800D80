#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tools/aic8800_prepare_mcu1_firmware.sh \
  --source-dir DIRECTORY \
  --output-dir NEW_DIRECTORY

Verify a user-supplied MCU1 firmware set and copy it under the safe,
revision-specific filenames used by the driver. The output directory must not
already exist.
EOF
}

source_dir=''
output_dir=''
while (( $# )); do
    case "$1" in
        --source-dir)
            (( $# >= 2 )) || { echo "ERROR: --source-dir requires a value" >&2; exit 2; }
            source_dir=$2
            shift 2
            ;;
        --output-dir)
            (( $# >= 2 )) || { echo "ERROR: --output-dir requires a value" >&2; exit 2; }
            output_dir=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$source_dir" || -z "$output_dir" ]]; then
    echo "ERROR: --source-dir and --output-dir are required" >&2
    usage >&2
    exit 2
fi
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
manifest="$repo_root/firmware/aic8800d80-mcu1.manifest"
source_dir=$(realpath -e -- "$source_dir")
resolved_output=$(realpath -m -- "$output_dir")
output_parent=$(dirname -- "$resolved_output")
if [[ -e "$resolved_output" ]]; then
    echo "ERROR: output path already exists: $resolved_output" >&2
    exit 3
fi
mkdir -p -- "$output_parent"

"$script_dir/verify_mcu1_profile.sh" --source-dir "$source_dir"

staging_dir=$(mktemp -d "$output_parent/.aic8800-mcu1.XXXXXX")
cleanup() {
    if [[ -n "${staging_dir:-}" && -d "$staging_dir" ]]; then
        rm -rf -- "$staging_dir"
    fi
}
trap cleanup EXIT

: > "$staging_dir/SHA256SUMS"
while read -r expected_hash expected_size source_name target_name; do
    [[ -n "$expected_hash" && ${expected_hash:0:1} != '#' ]] || continue
    if [[ -f "$source_dir/$target_name" ]]; then
        source_path="$source_dir/$target_name"
    else
        source_path="$source_dir/$source_name"
    fi
    install -m0644 -- "$source_path" "$staging_dir/$target_name"
    printf '%s  %s\n' "$expected_hash" "$target_name" >> "$staging_dir/SHA256SUMS"
done < "$manifest"

"$script_dir/verify_mcu1_profile.sh" --source-dir "$staging_dir"
mv -- "$staging_dir" "$resolved_output"
staging_dir=''
printf 'prepared_firmware_dir=%s\n' "$resolved_output"
