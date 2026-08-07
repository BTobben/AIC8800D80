#!/usr/bin/env bash
set -euo pipefail

# One-shot privileged acceptance test for exact driver/firmware packages and a USB port.
# This script deliberately refuses ambiguous USB layouts and never enables the
# experimental direct-HCI path in aic_btusb.

usage() {
    cat <<'EOF'
Usage:
  sudo tools/aic8800_install_mcu1_and_validate.sh \
    --driver-package PATH \
    --driver-package-sha256 SHA256 \
    --firmware-package PATH \
    --firmware-package-sha256 SHA256 \
    --usb-device /sys/bus/usb/devices/DEVICE \
    --port-disable /sys/bus/usb/devices/.../disable \
    --yes

This destructive acceptance test installs the supplied firmware-free driver
package and local firmware package, unloads the active AIC/Bluetooth modules,
and power-cycles one explicitly selected USB hub port. It refuses to run when
more than one supported AIC D80 device is present.
EOF
}

driver_package=''
driver_package_sha256=''
firmware_package=''
firmware_package_sha256=''
usb_device=''
hub_port_disable=''
confirmed=0

require_value() {
    if (( $# < 2 )); then
        echo "ERROR: $1 requires a value" >&2
        usage >&2
        exit 2
    fi
}

while (( $# )); do
    case "$1" in
        --driver-package)
            require_value "$@"
            driver_package=${2:-}
            shift 2
            ;;
        --driver-package-sha256)
            require_value "$@"
            driver_package_sha256=${2:-}
            shift 2
            ;;
        --firmware-package)
            require_value "$@"
            firmware_package=${2:-}
            shift 2
            ;;
        --firmware-package-sha256)
            require_value "$@"
            firmware_package_sha256=${2:-}
            shift 2
            ;;
        --usb-device)
            require_value "$@"
            usb_device=${2:-}
            shift 2
            ;;
        --port-disable)
            require_value "$@"
            hub_port_disable=${2:-}
            shift 2
            ;;
        --yes)
            confirmed=1
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

if (( EUID != 0 )); then
    echo "ERROR: run this script through sudo" >&2
    exit 2
fi

if (( ! confirmed )); then
    echo "ERROR: --yes is required because this test installs packages and power-cycles USB" >&2
    exit 2
fi

if [[ -z "$driver_package" || -z "$driver_package_sha256" || \
      -z "$firmware_package" || -z "$firmware_package_sha256" || \
      -z "$usb_device" || -z "$hub_port_disable" ]]; then
    echo "ERROR: both package paths/hashes, --usb-device, and --port-disable are required" >&2
    usage >&2
    exit 2
fi

for supplied_hash in "$driver_package_sha256" "$firmware_package_sha256"; do
    if [[ ! "$supplied_hash" =~ ^[[:xdigit:]]{64}$ ]]; then
        echo "ERROR: package hashes must be 64-character SHA-256 values" >&2
        exit 2
    fi
done

case "$usb_device" in
    /sys/bus/usb/devices/*) ;;
    *)
        echo "ERROR: --usb-device must be below /sys/bus/usb/devices" >&2
        exit 2
        ;;
esac

case "$hub_port_disable" in
    /sys/bus/usb/devices/*/disable) ;;
    *)
        echo "ERROR: --port-disable must select a USB sysfs disable file" >&2
        exit 2
        ;;
esac

resolved_usb_device=$(readlink -f -- "$usb_device" 2>/dev/null || true)
resolved_port_disable=$(readlink -f -- "$hub_port_disable" 2>/dev/null || true)
case "$resolved_usb_device" in
    /sys/devices/*) ;;
    *)
        echo "ERROR: --usb-device does not resolve to a live USB sysfs device" >&2
        exit 2
        ;;
esac
case "$resolved_port_disable" in
    /sys/devices/*/disable) ;;
    *)
        echo "ERROR: --port-disable does not resolve to a live USB disable file" >&2
        exit 2
        ;;
esac

readonly driver_package
readonly driver_package_sha256=${driver_package_sha256,,}
readonly firmware_package
readonly firmware_package_sha256=${firmware_package_sha256,,}
readonly usb_device
readonly hub_port_disable
readonly run_dir="/tmp/aic8800-mcu1-integrated-$(date +%Y%m%d-%H%M%S)"
readonly log_file="$run_dir/run.log"

mkdir -p "$run_dir"
chmod 0755 "$run_dir"
exec > >(tee "$log_file") 2>&1

port_disabled=0
restore_port() {
    if (( port_disabled )); then
        printf '0\n' > "$hub_port_disable" || true
    fi
}
trap restore_port EXIT

for package_spec in \
    "$driver_package|$driver_package_sha256|driver" \
    "$firmware_package|$firmware_package_sha256|firmware"
do
    IFS='|' read -r package_path expected_package_sha256 package_role <<< "$package_spec"
    if [[ ! -f "$package_path" ]]; then
        echo "ERROR: $package_role package is missing: $package_path"
        exit 3
    fi
    actual_package_sha256=$(sha256sum "$package_path" | awk '{print $1}')
    if [[ "$actual_package_sha256" != "$expected_package_sha256" ]]; then
        echo "ERROR: $package_role package hash mismatch"
        exit 4
    fi
done

if [[ ! -r "$usb_device/idVendor" || ! -r "$usb_device/idProduct" ]]; then
    echo "ERROR: selected physical USB path is absent: $usb_device"
    exit 5
fi

initial_id="$(<"$usb_device/idVendor"):$(<"$usb_device/idProduct")"
case "$initial_id" in
    a69c:5721|a69c:8d80|a69c:8d81|368b:8d81) ;;
    *)
        echo "ERROR: selected USB path contains unexpected device $initial_id"
        exit 6
        ;;
esac

if [[ ! -w "$hub_port_disable" ]]; then
    echo "ERROR: cannot control the exact upstream USB port"
    exit 7
fi

supported_devices=0
for vendor_file in /sys/bus/usb/devices/*/idVendor; do
    [[ -r "$vendor_file" ]] || continue
    product_file=${vendor_file%/idVendor}/idProduct
    [[ -r "$product_file" ]] || continue
    candidate_id="$(<"$vendor_file"):$(<"$product_file")"
    case "$candidate_id" in
        a69c:5721|a69c:8d80|a69c:8d81|368b:8d81)
            (( supported_devices += 1 ))
            ;;
    esac
done

if (( supported_devices != 1 )); then
    echo "ERROR: expected exactly one supported AIC D80 device; found $supported_devices"
    exit 7
fi

if ! modinfo aic8800_fdrv >/dev/null 2>&1; then
    echo "ERROR: aic8800_fdrv is required for the runtime/Wi-Fi interface"
    exit 7
fi

started=$(date '+%F %T')
echo "run_dir=$run_dir"
echo "started=$started"
echo "initial_usb_id=$initial_id"
uname -a
pacman -Q aic8800-usb-dkms aic8800d80-dkms || true
dkms status || true
lsusb -t || true
lsmod | grep -E '^(aic|btusb|bluetooth)' || true

echo "Installing verified local MCU1 firmware and firmware-free driver packages"
pacman -U --noconfirm "$firmware_package" "$driver_package"

pacman -Q aic8800-usb-dkms aic8800-mcu1-firmware-local aic8800d80-dkms \
    | tee "$run_dir/packages-after-install.txt"
dkms status | tee "$run_dir/dkms-after-install.txt"

for entry in \
    'fmacfw_8800d80_u02_mcu1.bin 1ec680c2b63dcaa0e5d33c5fb6d1857d030f8145c05c385e243760388a61a0da' \
    'fw_adid_8800d80_u02_mcu1.bin a526cbd02fcdc495f049f3ad6b5933cb08cd984b16790c716a060d582fee1a56' \
    'fw_patch_8800d80_u02_mcu1.bin 3c5fa5bb678b835adbe42cfe0326074cf8aa5c6d3b93d16d2943b63ad4106b72' \
    'fw_patch_table_8800d80_u02_mcu1.bin 58c07eb4c79de6e6beff683686495dec152688f7de59816cfbe71a0c664ca7c8' \
    'lmacfw_rf_8800d80_u02_mcu1.bin 964a007438c88b2878461311641803b5891ac32483e090694f4bbc263375986d'
do
    read -r filename expected_sha256 <<< "$entry"
    installed_file="/usr/lib/firmware/aic8800D80/$filename"
    actual_sha256=$(sha256sum "$installed_file" | awk '{print $1}')
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        echo "ERROR: installed firmware hash mismatch: $filename"
        exit 8
    fi
    echo "firmware_ok=$filename"
done

echo "Stopping Bluetooth userspace and unloading the old in-memory modules"
systemctl stop bluetooth.service || true
hciconfig hci0 down 2>/dev/null || true
modprobe -r aic8800_fdrv 2>/dev/null || true
if lsmod | grep -q '^aic_btusb '; then
    rmmod aic_btusb
fi
modprobe -r aic_load_fw 2>/dev/null || true
modprobe -r btusb 2>/dev/null || true

for module in aic8800_fdrv aic_btusb aic_load_fw btusb; do
    if lsmod | grep -q "^${module} "; then
        echo "ERROR: module remained loaded: $module"
        exit 9
    fi
done

echo "Disconnecting exact USB hub port through $hub_port_disable"
printf '1\n' > "$hub_port_disable"
port_disabled=1
sleep 5

# Register the intended owners before reconnecting the device. The custom
# aic_btusb module is not loaded; if udev loads it from its alias, its default
# allow_d80_direct_hci=false guard must reject D80.
modprobe aic_load_fw diag_d80_handoff=1
modprobe btusb
modprobe aic8800_fdrv

echo "Reconnecting exact USB hub port through $hub_port_disable"
printf '0\n' > "$hub_port_disable"
port_disabled=0

last_state=''
for _ in $(seq 1 90); do
    if [[ -r "$usb_device/idVendor" && -r "$usb_device/idProduct" ]]; then
        current_id="$(<"$usb_device/idVendor"):$(<"$usb_device/idProduct")"
        interfaces='?'
        [[ -r "$usb_device/bNumInterfaces" ]] && interfaces=$(tr -d ' ' < "$usb_device/bNumInterfaces")
        current_state="$current_id/$interfaces"
        if [[ "$current_state" != "$last_state" ]]; then
            echo "usb_state=$current_state"
            last_state=$current_state
        fi
        if [[ "$current_id" == 'a69c:8d81' && "$interfaces" == '3' ]]; then
            break
        fi
    fi
    sleep 1
done

if [[ ! -r "$usb_device/idVendor" || ! -r "$usb_device/idProduct" ]]; then
    echo "ERROR: adapter did not return"
    exit 10
fi

final_id="$(<"$usb_device/idVendor"):$(<"$usb_device/idProduct")"
final_interfaces=$(tr -d ' ' < "$usb_device/bNumInterfaces")
echo "final_usb_id=$final_id"
echo "final_interfaces=$final_interfaces"

lsusb -t | tee "$run_dir/lsusb-tree-final.txt"

for interface_number in 0 1 2; do
    interface="$usb_device:1.$interface_number"
    if [[ ! -d "$interface" ]]; then
        echo "ERROR: expected interface $interface_number is absent"
        exit 11
    fi
    class="$(<"$interface/bInterfaceClass")/$(<"$interface/bInterfaceSubClass")/$(<"$interface/bInterfaceProtocol")"
    driver=none
    [[ -L "$interface/driver" ]] && driver=$(basename "$(readlink -f "$interface/driver")")
    echo "interface_${interface_number}=$class/$driver"
done

if [[ "$final_id" != 'a69c:8d81' || "$final_interfaces" != '3' ]]; then
    echo "ERROR: integrated profile did not expose expected runtime topology"
    exit 12
fi

for interface_number in 0 1; do
    interface="$usb_device:1.$interface_number"
    class="$(<"$interface/bInterfaceClass")/$(<"$interface/bInterfaceSubClass")/$(<"$interface/bInterfaceProtocol")"
    driver=$(basename "$(readlink -f "$interface/driver")")
    if [[ "$class" != 'e0/01/01' || "$driver" != 'btusb' ]]; then
        echo "ERROR: Bluetooth interface $interface_number has unexpected ownership"
        exit 13
    fi
done

interface="$usb_device:1.2"
class="$(<"$interface/bInterfaceClass")/$(<"$interface/bInterfaceSubClass")/$(<"$interface/bInterfaceProtocol")"
driver=$(basename "$(readlink -f "$interface/driver")")
if [[ "$class" != 'ff/ff/ff' || "$driver" != 'aic8800_fdrv' ]]; then
    echo "ERROR: runtime interface 2 has unexpected ownership"
    exit 14
fi

if [[ -e /sys/module/aic_btusb/parameters/allow_d80_direct_hci ]]; then
    direct_hci=$(< /sys/module/aic_btusb/parameters/allow_d80_direct_hci)
    echo "allow_d80_direct_hci=$direct_hci"
    if [[ "$direct_hci" != 'N' ]]; then
        echo "ERROR: direct-HCI diagnostic override is active"
        exit 15
    fi
fi

rfkill unblock bluetooth || true
systemctl start bluetooth.service
sleep 3
btmgmt power on
btmgmt info | tee "$run_dir/btmgmt-info.txt"
hciconfig -a | tee "$run_dir/hciconfig.txt"

set +e
timeout --signal=INT 12 btmgmt find | tee "$run_dir/btmgmt-find.txt"
scan_status=${PIPESTATUS[0]}
set -e
if [[ $scan_status -ne 0 && $scan_status -ne 124 && $scan_status -ne 130 ]]; then
    echo "ERROR: Bluetooth discovery failed with status $scan_status"
    exit 16
fi
discovery_count=$(grep -c 'dev_found:' "$run_dir/btmgmt-find.txt" || true)
echo "bluetooth_discovery_reports=$discovery_count"
if (( discovery_count == 0 )); then
    echo "ERROR: Bluetooth discovery completed without receiving a device report"
    exit 17
fi

iw dev | tee "$run_dir/iw-dev.txt"
if ! grep -q 'Interface ' "$run_dir/iw-dev.txt"; then
    echo "ERROR: aic8800_fdrv did not expose a Wi-Fi interface"
    exit 18
fi

# A live aic8800_fdrv replacement can race NetworkManager's existing
# wpa_supplicant instance.  In the observed failure wpa_supplicant tried
# nl80211 before the replacement interface had settled, silently fell back to
# WEXT, and then could scan but could never associate.  Recreate the supplicant
# interface after wlan0 is fully registered so the supported nl80211 connect
# path is selected.  This does not alter saved connections or their secrets.
if systemctl is-active --quiet NetworkManager.service && \
   systemctl is-active --quiet wpa_supplicant.service; then
    echo "Reinitializing Wi-Fi userspace after the driver replacement"
    systemctl restart wpa_supplicant.service
    # Give NetworkManager time to discard the old D-Bus interface before
    # looking for the newly acquired one.
    sleep 3

    wifi_ready=0
    for _ in $(seq 1 30); do
        # The old P2P object can remain visible briefly while the supplicant is
        # restarting. Require both the nl80211 companion and a fully reacquired
        # (not merely listed/unavailable) wlan0 device.
        nm_state=$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null || true)
        if grep -q '^p2p-dev-wlan0:wifi-p2p:' <<< "$nm_state" && \
           grep -Eq '^wlan0:wifi:(disconnected|connected)$' <<< "$nm_state"; then
            wifi_ready=1
            break
        fi
        sleep 1
    done

    if (( ! wifi_ready )); then
        echo "ERROR: NetworkManager did not reacquire wlan0"
        exit 19
    fi

    # On this exact stack NetworkManager creates the P2P management device only
    # when the nl80211 backend initialized successfully.  Its absence caught
    # the otherwise easy-to-miss WEXT fallback seen during hardware testing.
    echo "wifi_backend=nl80211"
fi

journalctl -k --since "$started" --no-pager > "$run_dir/kernel-full.txt"
grep -Ei 'aic|btusb|bluetooth|hci|chip_id|chip_mcu|firmware|5721|8d80|8d81|error|fail|timeout' \
    "$run_dir/kernel-full.txt" | tail -500 | tee "$run_dir/kernel-filtered.txt" || true

if ! grep -q 'AIC8800D80 MCU1: selecting complete Radxa SDK V3 firmware profile' "$run_dir/kernel-full.txt"; then
    echo "ERROR: hardware works, but this run did not prove the integrated loader executed"
    echo "A physical unplug/replug is required for cold-loader acceptance"
    exit 20
fi

if ! grep -q 'AIC8800D80 MCU1: enabled Bluetooth cache fix' "$run_dir/kernel-full.txt"; then
    echo "ERROR: integrated loader ran without proof of the MCU1 cache fix"
    exit 21
fi

if grep -Eq 'errors:[1-9]' "$run_dir/hciconfig.txt"; then
    echo "ERROR: HCI transport counters contain errors"
    exit 22
fi

echo "RESULT=PASS"
echo "result_dir=$run_dir"
