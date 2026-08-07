#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tools/verify_mcu1_profile.sh --source-dir DIRECTORY

Verify a user-supplied AIC8800D80 MCU1 firmware directory without changing it.
The directory may contain the original vendor filenames or the normalized
revision-specific _mcu1 filenames.
EOF
}

source_dir=''
while (( $# )); do
    case "$1" in
        --source-dir)
            if (( $# < 2 )); then
                echo "ERROR: --source-dir requires a value" >&2
                exit 2
            fi
            source_dir=$2
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

if [[ -z "$source_dir" ]]; then
    echo "ERROR: --source-dir is required" >&2
    usage >&2
    exit 2
fi

if [[ ! -d "$source_dir" ]]; then
    echo "ERROR: firmware source directory is missing: $source_dir" >&2
    exit 3
fi

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
manifest="$repo_root/firmware/aic8800d80-mcu1.manifest"
source_dir=$(realpath -e -- "$source_dir")
verified=0

while read -r expected_hash expected_size source_name target_name; do
    [[ -n "$expected_hash" && ${expected_hash:0:1} != '#' ]] || continue
    if [[ -f "$source_dir/$target_name" ]]; then
        selected="$source_dir/$target_name"
    elif [[ -f "$source_dir/$source_name" ]]; then
        selected="$source_dir/$source_name"
    else
        printf 'ERROR: missing firmware: %s (or vendor name %s)\n' \
            "$target_name" "$source_name" >&2
        exit 3
    fi

    actual_size=$(stat -c '%s' -- "$selected")
    actual_hash=$(sha256sum -- "$selected" | awk '{print $1}')
    if [[ "$actual_size" != "$expected_size" || "$actual_hash" != "$expected_hash" ]]; then
        printf 'ERROR: firmware mismatch: %s\n' "$selected" >&2
        printf 'expected_size=%s actual_size=%s\n' "$expected_size" "$actual_size" >&2
        printf 'expected_sha256=%s\nactual_sha256=%s\n' \
            "$expected_hash" "$actual_hash" >&2
        exit 4
    fi

    printf 'ok %s %s source=%s\n' "$expected_hash" "$target_name" "$(basename -- "$selected")"
    (( verified += 1 ))
done < "$manifest"

if (( verified != 5 )); then
    echo "ERROR: manifest did not describe exactly five firmware artifacts" >&2
    exit 5
fi

printf 'MCU1 firmware profile is complete and hash-verified (%d artifacts).\n' "$verified"
