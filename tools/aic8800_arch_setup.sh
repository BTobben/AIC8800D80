#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  tools/aic8800_arch_setup.sh \
    (--firmware-source DIRECTORY | --fetch-mcu1-firmware) \
    [--acknowledge-upstream-license-status] \
    [--wifi-package PACKAGE] \
    [--install | --build-only] \
    [--skip-dependencies] [--keep-work-dir] [--yes]

Build the firmware-free AIC8800 USB DKMS package and a local, hash-verified
AIC8800D80 MCU1 firmware package on Arch Linux. With --install, install the
packages through pacman after showing their hashes and requesting confirmation.

Firmware modes:
  --firmware-source DIRECTORY
      Use firmware already obtained from a vendor or other lawful source.
  --fetch-mcu1-firmware
      Explicitly download from the immutable upstream commit recorded by the
      project. Requires --acknowledge-upstream-license-status.

Wi-Fi:
  --wifi-package PACKAGE
      Optionally include a reviewed local aic8800d80-dkms package providing
      aic8800_fdrv. A moving AUR recipe is never executed automatically.

Safety:
  --build-only is the default and never installs packages.
  --install does not unload modules, reset USB, or restart networking.
EOF
}

firmware_source=''
fetch_firmware=0
acknowledged=0
install_packages=0
skip_dependencies=0
keep_work_dir=0
assume_yes=0
wifi_package=''

require_value() {
    if (( $# < 2 )); then
        echo "ERROR: $1 requires a value" >&2
        usage >&2
        exit 2
    fi
}

while (( $# )); do
    case "$1" in
        --firmware-source)
            require_value "$@"
            firmware_source=$2
            shift 2
            ;;
        --fetch-mcu1-firmware)
            fetch_firmware=1
            shift
            ;;
        --acknowledge-upstream-license-status)
            acknowledged=1
            shift
            ;;
        --wifi-package)
            require_value "$@"
            wifi_package=$2
            shift 2
            ;;
        --install)
            install_packages=1
            shift
            ;;
        --build-only)
            install_packages=0
            shift
            ;;
        --skip-dependencies)
            skip_dependencies=1
            shift
            ;;
        --keep-work-dir)
            keep_work_dir=1
            shift
            ;;
        --yes)
            assume_yes=1
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

if (( EUID == 0 )); then
    echo "ERROR: run this helper as a normal user; it invokes sudo only for pacman" >&2
    exit 2
fi
if [[ -n "$firmware_source" && $fetch_firmware -eq 1 ]]; then
    echo "ERROR: choose either --firmware-source or --fetch-mcu1-firmware" >&2
    exit 2
fi
if [[ -z "$firmware_source" && $fetch_firmware -eq 0 ]]; then
    echo "ERROR: a firmware source mode is required" >&2
    usage >&2
    exit 2
fi
if (( fetch_firmware && ! acknowledged )); then
    echo "ERROR: fetching requires --acknowledge-upstream-license-status" >&2
    exit 2
fi
if [[ ! -r /etc/arch-release ]] || ! command -v pacman >/dev/null 2>&1; then
    echo "ERROR: this guided installer currently supports Arch Linux only" >&2
    exit 3
fi

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
repo_ref=$(git -C "$repo_root" branch --show-current)
if [[ -z "$repo_ref" ]]; then
    echo "ERROR: the repository must be on a named branch for the local package build" >&2
    exit 3
fi

echo "repository=$repo_root"
echo "branch=$repo_ref"
echo "kernel=$(uname -r)"

candidate_count=0
for vendor_file in /sys/bus/usb/devices/*/idVendor; do
    [[ -r "$vendor_file" ]] || continue
    product_file=${vendor_file%/idVendor}/idProduct
    [[ -r "$product_file" ]] || continue
    candidate_id="$(<"$vendor_file"):$(<"$product_file")"
    case "$candidate_id" in
        a69c:5721|a69c:8d80|a69c:8d81|368b:8d81)
            echo "candidate_usb_id=$candidate_id sysfs=${vendor_file%/idVendor}"
            (( candidate_count += 1 ))
            ;;
    esac
done
if (( candidate_count == 0 )); then
    echo "NOTICE: no candidate AIC8800D80 USB identity is currently visible."
elif (( candidate_count > 1 )); then
    echo "NOTICE: multiple candidate identities are visible; installation is allowed,"
    echo "        but do not use the destructive acceptance runner on an ambiguous layout."
fi

install_dependency_packages() {
    local running_kernel kernel_pkgbase header_package
    local -a dependencies pacman_args

    running_kernel=$(uname -r)
    dependencies=(base-devel dkms git curl)
    if [[ -r "/usr/lib/modules/$running_kernel/pkgbase" ]]; then
        kernel_pkgbase=$(<"/usr/lib/modules/$running_kernel/pkgbase")
        if [[ "$kernel_pkgbase" =~ ^[A-Za-z0-9@._+-]+$ ]]; then
            header_package="${kernel_pkgbase}-headers"
            dependencies+=("$header_package")
        fi
    fi

    pacman_args=(-S --needed)
    if (( assume_yes )); then
        pacman_args+=(--noconfirm)
    fi
    echo "Installing/checking build dependencies: ${dependencies[*]}"
    sudo pacman "${pacman_args[@]}" "${dependencies[@]}"
}

if (( install_packages && ! skip_dependencies )); then
    install_dependency_packages
fi

required_commands=(git makepkg sha256sum realpath)
if (( fetch_firmware )); then
    required_commands+=(curl)
fi
for required_command in "${required_commands[@]}"; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "ERROR: required command is missing: $required_command" >&2
        echo "Rerun with --install, or install the documented Arch build dependencies." >&2
        exit 3
    fi
done

kernel_build_tree="/usr/lib/modules/$(uname -r)/build/Makefile"
if [[ ! -r "$kernel_build_tree" ]]; then
    echo "ERROR: matching headers are missing: $kernel_build_tree" >&2
    exit 3
fi

if [[ -n "$wifi_package" ]]; then
    wifi_package=$(realpath -e -- "$wifi_package")
    wifi_package_name=$(pacman -Qp -- "$wifi_package" | awk 'NR == 1 {print $1}')
    if [[ "$wifi_package_name" != 'aic8800d80-dkms' ]]; then
        echo "ERROR: --wifi-package must provide aic8800d80-dkms, not $wifi_package_name" >&2
        exit 4
    fi
    echo "wifi_runtime_package=$wifi_package"
elif pacman -Q aic8800d80-dkms >/dev/null 2>&1; then
    echo "wifi_runtime=$(pacman -Q aic8800d80-dkms)"
else
    echo "WARNING: aic8800d80-dkms is not installed or supplied."
    echo "         Bluetooth/loader packages will be built, but Wi-Fi needs aic8800_fdrv."
fi

work_dir=$(mktemp -d /tmp/aic8800-arch-setup.XXXXXX)
packages_dir="$work_dir/packages"
mkdir -p -- "$packages_dir"

cleanup() {
    if (( install_packages && ! keep_work_dir )); then
        rm -rf -- "$work_dir"
    else
        echo "work_dir=$work_dir"
    fi
}
trap cleanup EXIT

if (( fetch_firmware )); then
    prepared_firmware="$work_dir/firmware"
    "$script_dir/aic8800_fetch_mcu1_firmware.sh" \
        --output-dir "$prepared_firmware" \
        --acknowledge-upstream-license-status
else
    firmware_source=$(realpath -e -- "$firmware_source")
    prepared_firmware="$work_dir/firmware"
    "$script_dir/aic8800_prepare_mcu1_firmware.sh" \
        --source-dir "$firmware_source" \
        --output-dir "$prepared_firmware"
fi

"$script_dir/aic8800_build_mcu1_firmware_package.sh" \
    --source-dir "$prepared_firmware" \
    --output-dir "$packages_dir"

driver_build_dir="$work_dir/driver-package"
cp -a -- "$repo_root/packaging/arch/aic8800-usb-dkms" "$driver_build_dir"
(
    cd "$driver_build_dir"
    AIC8800_REPO_URL="file://$repo_root" \
        AIC8800_REPO_REF="$repo_ref" \
        PKGDEST="$packages_dir" \
        makepkg -Csf --noconfirm
)

firmware_package=$(find "$packages_dir" -maxdepth 1 -type f \
    -name 'aic8800-mcu1-firmware-local-*.pkg.tar.*' -printf '%T@ %p\n' \
    | sort -n | tail -n 1 | cut -d' ' -f2-)
driver_package=$(find "$packages_dir" -maxdepth 1 -type f \
    -name 'aic8800-usb-dkms-*.pkg.tar.*' -printf '%T@ %p\n' \
    | sort -n | tail -n 1 | cut -d' ' -f2-)
if [[ -z "$firmware_package" || -z "$driver_package" ]]; then
    echo "ERROR: expected package output is missing" >&2
    exit 5
fi

echo "Built packages:"
sha256sum -- "$firmware_package" "$driver_package"
if [[ -n "$wifi_package" ]]; then
    sha256sum -- "$wifi_package"
fi

if (( ! install_packages )); then
    echo "RESULT=BUILT"
    exit 0
fi

if (( ! assume_yes )); then
    printf 'Install the displayed packages with pacman? [y/N] '
    read -r confirmation
    case "$confirmation" in
        y|Y|yes|YES) ;;
        *)
            echo "Installation cancelled; packages remain in $packages_dir"
            keep_work_dir=1
            exit 0
            ;;
    esac
fi

packages_to_install=("$firmware_package" "$driver_package")
if [[ -n "$wifi_package" ]]; then
    packages_to_install=("$wifi_package" "${packages_to_install[@]}")
fi
pacman_install_args=(-U)
if (( assume_yes )); then
    pacman_install_args+=(--noconfirm)
fi
sudo pacman "${pacman_install_args[@]}" "${packages_to_install[@]}"

"$script_dir/verify_mcu1_profile.sh" \
    --source-dir /usr/lib/firmware/aic8800D80
pacman -Q aic8800-usb-dkms aic8800-mcu1-firmware-local
pacman -Q aic8800d80-dkms 2>/dev/null || \
    echo "wifi_runtime=missing (aic8800_fdrv is required for Wi-Fi)"
dkms status || true

cat <<'EOF'
RESULT=INSTALLED

Reboot or unplug/reconnect the adapter before functional testing. This helper
does not disrupt active Bluetooth, networking, or USB sessions automatically.

Verify afterwards with:
  lsusb -t
  ip link
  bluetoothctl list
  sudo journalctl -k -b | grep -iE 'aic|btusb|bluetooth|firmware'
EOF
