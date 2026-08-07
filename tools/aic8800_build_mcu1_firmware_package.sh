#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tools/aic8800_build_mcu1_firmware_package.sh \
  --source-dir DIRECTORY \
  --output-dir DIRECTORY

Build a local Arch package from a user-supplied, hash-verified MCU1 firmware
set. The resulting package must not be uploaded without redistribution rights.
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

if (( EUID == 0 )); then
    echo "ERROR: build the local package as an unprivileged user" >&2
    exit 2
fi
if [[ -z "$source_dir" || -z "$output_dir" ]]; then
    echo "ERROR: --source-dir and --output-dir are required" >&2
    usage >&2
    exit 2
fi
if ! command -v makepkg >/dev/null 2>&1; then
    echo "ERROR: makepkg is required" >&2
    exit 3
fi

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
source_dir=$(realpath -e -- "$source_dir")
mkdir -p -- "$output_dir"
output_dir=$(realpath -e -- "$output_dir")

"$script_dir/verify_mcu1_profile.sh" --source-dir "$source_dir"

build_dir=$(mktemp -d /tmp/aic8800-mcu1-package.XXXXXX)
cleanup() {
    rm -rf -- "$build_dir"
}
trap cleanup EXIT
cp -- "$repo_root/packaging/arch/aic8800-mcu1-firmware-local/PKGBUILD" "$build_dir/PKGBUILD"

(
    cd "$build_dir"
    AIC8800_MCU1_FIRMWARE_DIR="$source_dir" PKGDEST="$output_dir" \
        makepkg -Csf --noconfirm
)

package=$(find "$output_dir" -maxdepth 1 -type f \
    -name 'aic8800-mcu1-firmware-local-*.pkg.tar.*' -printf '%T@ %p\n' \
    | sort -n | tail -n 1 | cut -d' ' -f2-)
if [[ -z "$package" ]]; then
    echo "ERROR: makepkg did not create the expected package" >&2
    exit 4
fi
sha256sum -- "$package"
echo "NOTICE: local-use package only; do not attach it to a public release."
