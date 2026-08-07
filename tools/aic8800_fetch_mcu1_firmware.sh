#!/usr/bin/env bash
set -euo pipefail

readonly upstream_repository='https://github.com/shenmintao/aic8800d80'
readonly upstream_commit='fffad12a26ba562435783e1be855736e1dec8c1b'
readonly upstream_raw_base="https://raw.githubusercontent.com/shenmintao/aic8800d80/${upstream_commit}/fw/aic8800D80"

usage() {
    cat <<'EOF'
Usage: tools/aic8800_fetch_mcu1_firmware.sh \
  --output-dir NEW_DIRECTORY \
  --acknowledge-upstream-license-status

Opt in to downloading the five MCU1 firmware files directly from the pinned
public upstream commit, verify every size and SHA-256 value, and store them
under the revision-specific local names used by the driver.

The upstream repository does not publish a detected redistribution license for
these files. This tool does not grant additional rights. Review the upstream
source and applicable terms before proceeding. Never publish its output as a
project release artifact without permission from the rights holder.
EOF
}

output_dir=''
acknowledged=0
while (( $# )); do
    case "$1" in
        --output-dir)
            (( $# >= 2 )) || { echo "ERROR: --output-dir requires a value" >&2; exit 2; }
            output_dir=$2
            shift 2
            ;;
        --acknowledge-upstream-license-status)
            acknowledged=1
            shift
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

cat >&2 <<EOF
NOTICE: MCU1 firmware will be downloaded directly from:
  repository: $upstream_repository
  commit:     $upstream_commit

No redistribution license for these firmware files is detected upstream.
The download is optional, locally initiated, and not performed by CI or release
automation. You are responsible for confirming that your use is permitted.
EOF

if (( ! acknowledged )); then
    echo "ERROR: explicit --acknowledge-upstream-license-status is required" >&2
    exit 2
fi
if [[ -z "$output_dir" ]]; then
    echo "ERROR: --output-dir is required" >&2
    usage >&2
    exit 2
fi
if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl is required" >&2
    exit 3
fi

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
manifest="$repo_root/firmware/aic8800d80-mcu1.manifest"
resolved_output=$(realpath -m -- "$output_dir")
output_parent=$(dirname -- "$resolved_output")
if [[ -e "$resolved_output" ]]; then
    echo "ERROR: output path already exists: $resolved_output" >&2
    exit 3
fi
mkdir -p -- "$output_parent"

case "$resolved_output/" in
    "$repo_root/"*)
        echo "ERROR: keep downloaded firmware outside the Git worktree" >&2
        exit 3
        ;;
esac

staging_dir=$(mktemp -d "$output_parent/.aic8800-mcu1-fetch.XXXXXX")
cleanup() {
    if [[ -n "${staging_dir:-}" && -d "$staging_dir" ]]; then
        rm -rf -- "$staging_dir"
    fi
}
trap cleanup EXIT

: > "$staging_dir/SHA256SUMS"
verified=0
while read -r expected_hash expected_size source_name target_name; do
    [[ -n "$expected_hash" && ${expected_hash:0:1} != '#' ]] || continue
    download_path="$staging_dir/.download-$source_name"
    download_url="$upstream_raw_base/$source_name"

    printf 'fetching %s\n' "$download_url"
    curl --fail --location --silent --show-error \
        --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --retry 2 --connect-timeout 15 \
        --max-time 120 --output "$download_path" -- "$download_url"

    actual_size=$(stat -c '%s' -- "$download_path")
    actual_hash=$(sha256sum -- "$download_path" | awk '{print $1}')
    if [[ "$actual_size" != "$expected_size" || "$actual_hash" != "$expected_hash" ]]; then
        printf 'ERROR: downloaded firmware mismatch: %s\n' "$source_name" >&2
        printf 'expected_size=%s actual_size=%s\n' \
            "$expected_size" "$actual_size" >&2
        printf 'expected_sha256=%s\nactual_sha256=%s\n' \
            "$expected_hash" "$actual_hash" >&2
        exit 4
    fi

    mv -- "$download_path" "$staging_dir/$target_name"
    chmod 0644 "$staging_dir/$target_name"
    printf '%s  %s\n' "$expected_hash" "$target_name" \
        >> "$staging_dir/SHA256SUMS"
    printf 'verified %s\n' "$target_name"
    (( verified += 1 ))
done < "$manifest"

if (( verified != 5 )); then
    echo "ERROR: manifest did not describe exactly five firmware artifacts" >&2
    exit 5
fi

cat > "$staging_dir/UPSTREAM_SOURCE.txt" <<EOF
Repository: $upstream_repository
Commit: $upstream_commit
Firmware path: fw/aic8800D80
License status: no redistribution license detected by this project
EOF

"$script_dir/verify_mcu1_profile.sh" --source-dir "$staging_dir"
mv -- "$staging_dir" "$resolved_output"
staging_dir=''

printf 'downloaded_firmware_dir=%s\n' "$resolved_output"
echo "NOTICE: local use only; do not commit, cache, mirror, or publish this directory."
