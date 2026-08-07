#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
RESET_TIMELINE_MODE=""
USBMON=0
OUT_DIR=""
RESET_WINDOW_SINCE=""
PRE_IOCTL_DELAY_MS=0
POST_IOCTL_DELAY_MS=0
USB_SYSFS_ROOT=${AIC_USB_SYSFS_ROOT:-/sys/bus/usb/devices}
PROFILE_LOG=""

usage() {
  cat <<'EOF'
Usage: tools/aic_bt_collect_debug.sh [OUT_DIR]
       tools/aic_bt_collect_debug.sh --reset-timeline ep1 [--pre-ioctl-delay-ms N] [--post-ioctl-delay-ms N] [--usbmon] [OUT_DIR]
       tools/aic_bt_collect_debug.sh --reset-timeline ep2 [--pre-ioctl-delay-ms N] [--post-ioctl-delay-ms N] [--usbmon] [OUT_DIR]
       tools/aic_bt_collect_debug.sh --reset-timeline ep0 [--pre-ioctl-delay-ms N] [--post-ioctl-delay-ms N] [--usbmon] [OUT_DIR]
       tools/aic_bt_collect_debug.sh --profile-log FILE [OUT_DIR]

Collect AIC Bluetooth diagnostics. The reset-timeline modes run only the existing
safe char-session Reset probe (H4 Reset 01 03 0c 00) after verifying live
/sys/module/aic_btusb/parameters/diag_reset_timeline is present and enabled.
The default mode is read-only and records USB interface/endpoint topology,
driver aliases, installed-package ownership, and firmware hashes. Reset modes
are refused for a 368b:8d81 runtime exposing only a vendor-specific interface
without an interrupt-IN endpoint; that topology is not a source-proven HCI
transport.

Modes:
  ep1  Require diag_reset_timeline=Y and set diag_hci_cmd_use_param_ep=N.
  ep2  Require diag_reset_timeline=Y, set hci_cmd_out_ep=2, and set
       diag_hci_cmd_use_param_ep=Y.
  ep0  Set/require diag_reset_timeline=Y, set diag_hci_cmd_reset_ep0=Y,
       diag_hci_cmd_use_param_ep=N, and diag_hci_cmd_h4_prefix=N.

Options:
  --pre-ioctl-delay-ms N   Sleep after opening /dev/aicbt_dev before GET_USB_INFO.
  --post-ioctl-delay-ms N  Sleep after GET_USB_INFO before the Reset write.
  --usbmon  Optionally capture usbmon text output while the Reset probe runs.
  --profile-log FILE  Assess D80 chip/profile provenance from an existing kernel log.
  -h, --help  Show this help.
EOF
}

while (($#)); do
  case "$1" in
    --reset-timeline)
      [[ $# -ge 2 ]] || { echo "ERROR: --reset-timeline requires ep0, ep1, or ep2" >&2; exit 2; }
      RESET_TIMELINE_MODE="$2"
      shift 2
      ;;
    --reset-timeline=*)
      RESET_TIMELINE_MODE="${1#*=}"
      shift
      ;;
    --pre-ioctl-delay-ms)
      [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || { echo "ERROR: --pre-ioctl-delay-ms requires a non-negative integer" >&2; exit 2; }
      PRE_IOCTL_DELAY_MS="$2"
      shift 2
      ;;
    --post-ioctl-delay-ms)
      [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || { echo "ERROR: --post-ioctl-delay-ms requires a non-negative integer" >&2; exit 2; }
      POST_IOCTL_DELAY_MS="$2"
      shift 2
      ;;
    --usbmon)
      USBMON=1
      shift
      ;;
    --profile-log)
      [[ $# -ge 2 && -f "$2" && -r "$2" ]] || { echo "ERROR: --profile-log requires a readable file" >&2; exit 2; }
      PROFILE_LOG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$OUT_DIR" ]]; then
        echo "ERROR: multiple output directories specified: $OUT_DIR and $1" >&2
        exit 2
      fi
      OUT_DIR="$1"
      shift
      ;;
  esac
done

case "$RESET_TIMELINE_MODE" in
  ""|ep0|ep1|ep2) ;;
  *)
    echo "ERROR: --reset-timeline must be ep0, ep1, or ep2, got: $RESET_TIMELINE_MODE" >&2
    exit 2
    ;;
esac

OUT_DIR=${OUT_DIR:-"logs/$(date +%Y%m%d-%H%M%S)-$(uname -r)"}
mkdir -p "$OUT_DIR"

find_aic_usb_dev() {
  local d vid pid
  for d in "$USB_SYSFS_ROOT"/*; do
    [[ -f "$d/idVendor" && -f "$d/idProduct" ]] || continue
    vid=$(<"$d/idVendor")
    pid=$(<"$d/idProduct")
    case "${vid}:${pid}" in
      a69c:5721|a69c:8d80|a69c:8d81|368b:8d81)
        basename "$d"
        return 0
        ;;
    esac
  done
  return 1
}

run_capture() {
  local name="$1"
  shift
  {
    echo "# $*"
    "$@"
  } >"$OUT_DIR/$name" 2>&1 || true
}

run_capture_sudo() {
  local name="$1"
  shift
  {
    echo "# sudo $*"
    sudo "$@"
  } >"$OUT_DIR/$name" 2>&1 || true
}

run_capture_git() {
  local name="$1"
  shift
  if [[ -n "$REPO_ROOT" ]]; then
    run_capture "$name" git -C "$REPO_ROOT" "$@"
  else
    printf 'not run from inside a git worktree\n' >"$OUT_DIR/$name"
  fi
}

capture_usbmon_debugfs_state() {
  local usbmon_path="/sys/kernel/debug/usb/usbmon/0u"
  {
    echo '# mount | grep debugfs'
    mount | grep debugfs || true
    echo
    echo '# lsmod | grep usbmon'
    lsmod | grep usbmon || true
    echo
    echo '# sudo ls -ld /sys/kernel/debug /sys/kernel/debug/usb /sys/kernel/debug/usb/usbmon'
    sudo ls -ld /sys/kernel/debug /sys/kernel/debug/usb /sys/kernel/debug/usb/usbmon || true
    echo
    echo '# sudo ls -l /sys/kernel/debug/usb/usbmon'
    sudo ls -l /sys/kernel/debug/usb/usbmon || true
    echo
    echo "# sudo test -e $usbmon_path"
    if sudo test -e "$usbmon_path"; then
      echo 'exists=yes'
    else
      echo 'exists=no'
    fi
    echo
    echo "# sudo test -r $usbmon_path"
    if sudo test -r "$usbmon_path"; then
      echo 'readable=yes'
    else
      echo 'readable=no'
    fi
  } >"$OUT_DIR/usbmon-debugfs-state.txt" 2>&1
}

sysfs_param_path() {
  local param="$1"
  printf '/sys/module/aic_btusb/parameters/%s' "$param"
}

write_sysfs_param() {
  local param="$1" value="$2" path
  path=$(sysfs_param_path "$param")
  if [[ ! -e "$path" ]]; then
    echo "ERROR: missing live aic_btusb parameter: $param ($path)" >&2
    echo "       modinfo may point to a new module on disk while an older aic_btusb is still loaded." >&2
    echo "       Reload manually, for example: sudo rmmod aic_btusb; sudo modprobe -v aic_btusb_usb diag_reset_timeline=1 ..." >&2
    return 1
  fi
  printf '%s\n' "$value" | sudo tee "$path" >/dev/null
}

capture_live_aic_params() {
  local param path
  for param in diag_reset_timeline diag_hci_cmd_reset_ep0 diag_hci_cmd_use_param_ep diag_hci_cmd_h4_prefix hci_cmd_out_ep; do
    path=$(sysfs_param_path "$param")
    if [[ -e "$path" ]]; then
      printf '%s=' "$param"
      cat "$path"
    else
      printf '%s=MISSING (%s)\n' "$param" "$path"
    fi
  done
}

capture_zlp_status() {
  local module_root=/sys/module/aic_zlp_quirk

  if [[ ! -d "$module_root" ]]; then
    echo 'loaded=no'
    return 0
  fi

  echo 'loaded=yes'
  for param in hook injections; do
    if [[ -r "$module_root/parameters/$param" ]]; then
      printf '%s=' "$param"
      cat "$module_root/parameters/$param"
    else
      printf '%s=unavailable\n' "$param"
    fi
  done
}

require_diag_reset_enabled() {
  local path value
  path=$(sysfs_param_path diag_reset_timeline)
  if [[ ! -e "$path" ]]; then
    echo "ERROR: diag_reset_timeline live sysfs parameter is missing at $path" >&2
    echo "       modinfo may show the new DKMS module on disk while an older aic_btusb remains loaded." >&2
    echo "       Reload manually, for example: sudo rmmod aic_btusb; sudo modprobe -v aic_btusb_usb diag_reset_timeline=1 diag_hci_cmd_use_param_ep=0" >&2
    return 1
  fi
  value=$(cat "$path")
  if [[ "$value" != "Y" && "$value" != "1" ]]; then
    echo "ERROR: diag_reset_timeline is not enabled in live sysfs (value=$value at $path)" >&2
    echo "       Reload or enable the module parameter before running --reset-timeline." >&2
    return 1
  fi
}

configure_reset_timeline_mode() {
  local mode="$1"
  write_sysfs_param diag_reset_timeline Y
  require_diag_reset_enabled
  case "$mode" in
    ep0)
      write_sysfs_param diag_hci_cmd_reset_ep0 Y
      write_sysfs_param diag_hci_cmd_use_param_ep N
      write_sysfs_param diag_hci_cmd_h4_prefix N
      ;;
    ep1)
      write_sysfs_param diag_hci_cmd_reset_ep0 N
      write_sysfs_param diag_hci_cmd_use_param_ep N
      ;;
    ep2)
      write_sysfs_param diag_hci_cmd_reset_ep0 N
      write_sysfs_param hci_cmd_out_ep 2
      write_sysfs_param diag_hci_cmd_use_param_ep Y
      ;;
  esac
  capture_live_aic_params >"$OUT_DIR/live-aicbt-params-after-mode.txt"
}

compile_char_session_probe() {
  local src bin
  if [[ -n "$REPO_ROOT" ]]; then
    src="$REPO_ROOT/tools/aicbt_char_session_probe.c"
  else
    src="$SCRIPT_DIR/aicbt_char_session_probe.c"
  fi
  bin="/tmp/aicbt_char_session_probe"
  if [[ ! -f "$src" ]]; then
    echo "ERROR: missing probe source: $src" >&2
    return 1
  fi
  cc -Wall -Wextra -O2 -o "$bin" "$src"
  printf '%s\n' "$bin"
}

run_reset_timeline_probe() {
  local probe_bin usbmon_pid="" probe_status=0 probe_failed=0
  local -a probe_args
  probe_bin=$(compile_char_session_probe)
  echo "$probe_bin" >"$OUT_DIR/char-session-probe-path.txt"
  printf 'pre_ioctl_delay_ms=%s\npost_ioctl_delay_ms=%s\n' \
    "$PRE_IOCTL_DELAY_MS" "$POST_IOCTL_DELAY_MS" >"$OUT_DIR/reset-timeline-delays.txt"

  probe_args=(--timeout-ms 10000)
  if [[ "$PRE_IOCTL_DELAY_MS" != "0" ]]; then
    probe_args+=(--pre-ioctl-delay-ms "$PRE_IOCTL_DELAY_MS")
  fi
  if [[ "$POST_IOCTL_DELAY_MS" != "0" ]]; then
    probe_args+=(--post-ioctl-delay-ms "$POST_IOCTL_DELAY_MS")
  fi
  probe_args+=(--send-reset)

  RESET_WINDOW_SINCE=$(date '+%F %T')
  printf '%s\n' "$RESET_WINDOW_SINCE" >"$OUT_DIR/reset-window-since.txt"

  if (( USBMON )); then
    local usbmon_path="/sys/kernel/debug/usb/usbmon/0u"
    run_capture_sudo usbmon-modprobe.txt modprobe usbmon
    capture_usbmon_debugfs_state
    if ! sudo test -e "$usbmon_path"; then
      {
        printf 'usbmon capture unavailable: %s does not exist. Is debugfs mounted and usbmon loaded?\n' "$usbmon_path"
        printf 'See usbmon-debugfs-state.txt for mount, module, and debugfs listing details.\n'
      } >"$OUT_DIR/usbmon-0u-reset.err"
    elif ! sudo test -r "$usbmon_path"; then
      {
        printf 'usbmon capture unavailable: %s is not readable via sudo. Check debugfs permissions.\n' "$usbmon_path"
        printf 'See usbmon-debugfs-state.txt for mount, module, and debugfs listing details.\n'
      } >"$OUT_DIR/usbmon-0u-reset.err"
    else
      printf 'sudo timeout 15s cat %s\n' "$usbmon_path" >"$OUT_DIR/usbmon-0u-reset-command.txt"
      sudo timeout 15s cat "$usbmon_path" >"$OUT_DIR/usbmon-0u-reset.txt" 2>"$OUT_DIR/usbmon-0u-reset.err" &
      usbmon_pid=$!
      sleep 1
    fi
  fi

  set +e
  {
    printf '# sudo %q' "$probe_bin"
    printf ' %q' "${probe_args[@]}"
    printf '\n'
    sudo "$probe_bin" "${probe_args[@]}"
  } >"$OUT_DIR/char-session-reset-probe.txt" 2>&1
  probe_status=$?
  set -e

  if [[ -n "$usbmon_pid" ]]; then
    wait "$usbmon_pid" || true
  fi

  {
    printf 'probe_exit_status=%d\n' "$probe_status"
    if (( probe_status != 0 )); then
      printf 'PROBE_FAILED: sudo char-session Reset probe exited with status %d\n' "$probe_status"
      probe_failed=1
    fi
    if grep -q 'open_ret=-1' "$OUT_DIR/char-session-reset-probe.txt"; then
      printf 'PROBE_FAILED: char-session Reset probe output contains open_ret=-1\n'
      probe_failed=1
    fi
    if (( probe_failed == 0 )); then
      printf 'probe_result=ok\n'
    fi
  } >"$OUT_DIR/char-session-reset-probe-status.txt"

  if (( probe_failed != 0 )); then
    echo "WARNING: reset-timeline probe failed; see $OUT_DIR/char-session-reset-probe-status.txt and char-session-reset-probe.txt" >&2
  fi
}

capture_reset_window_journal() {
  [[ -n "$RESET_WINDOW_SINCE" ]] || return 0
  run_capture_sudo journal-reset-window.txt journalctl -k --since "$RESET_WINDOW_SINCE"
  grep -iE 'diag_reset:|runtime_cmd_tx|CMD TX submit bulk|TX complete|intr_complete|read_data|aic|btusb|bluetooth|hci0|0x0c03|firmware|timeout|-110' \
    "$OUT_DIR/journal-reset-window.txt" >"$OUT_DIR/journal-reset-window-filtered.txt" 2>/dev/null || true
}

capture_usb_sysfs() {
  local usb_dev="$1"
  local base="${USB_SYSFS_ROOT}/${usb_dev}"
  local iface ep driver

  echo "usb_dev=$usb_dev"
  echo "sysfs_path=$base"

  [[ -d "$base" ]] || return 0

  for field in idVendor idProduct product manufacturer bDeviceClass bDeviceSubClass bDeviceProtocol bNumInterfaces; do
    [[ -f "$base/$field" ]] || continue
    printf '%s=' "$field"
    cat "$base/$field"
  done
  if [[ -f "$base/power/control" ]]; then
    printf 'power_control='
    cat "$base/power/control"
  fi

  for iface in "$base":*; do
    [[ -d "$iface" ]] || continue
    printf '\n[interface %s]\n' "${iface##*:}"
    for field in bInterfaceNumber bInterfaceClass bInterfaceSubClass bInterfaceProtocol bNumEndpoints; do
      [[ -f "$iface/$field" ]] || continue
      printf '%s=' "$field"
      cat "$iface/$field"
    done
    if [[ -L "$iface/driver" ]]; then
      driver=$(readlink -f "$iface/driver")
      printf 'driver=%s\n' "${driver##*/}"
    else
      printf 'driver=none\n'
    fi

    for ep in "$iface"/ep_*; do
      [[ -d "$ep" ]] || continue
      printf '[endpoint %s]\n' "${ep##*/}"
      for field in bEndpointAddress bmAttributes direction type wMaxPacketSize interval; do
        [[ -f "$ep/$field" ]] || continue
        printf '%s=' "$field"
        cat "$ep/$field"
      done
    done
  done

  return 0
}

runtime_transport_is_unproven() {
  local usb_dev="$1"
  local base="${USB_SYSFS_ROOT}/${usb_dev}"
  local vid pid iface cls sub proto ep ep_type ep_dir
  local interface_count=0 hci_interface_count=0 vendor_interface_count=0 interrupt_in_count=0

  [[ -f "$base/idVendor" && -f "$base/idProduct" ]] || return 1
  vid=$(<"$base/idVendor")
  pid=$(<"$base/idProduct")
  case "${vid,,}:${pid,,}" in
    a69c:8d81|368b:8d81) ;;
    *) return 1 ;;
  esac

  for iface in "$base":*; do
    [[ -d "$iface" ]] || continue
    ((interface_count += 1))
    [[ -f "$iface/bInterfaceClass" ]] && cls=$(<"$iface/bInterfaceClass") || cls=""
    [[ -f "$iface/bInterfaceSubClass" ]] && sub=$(<"$iface/bInterfaceSubClass") || sub=""
    [[ -f "$iface/bInterfaceProtocol" ]] && proto=$(<"$iface/bInterfaceProtocol") || proto=""
    if [[ "${cls,,}:${sub,,}:${proto,,}" == "e0:01:01" ]]; then
      ((hci_interface_count += 1))
    fi
    if [[ "${cls,,}:${sub,,}:${proto,,}" == "ff:ff:ff" ]]; then
      ((vendor_interface_count += 1))
    fi
    for ep in "$iface"/ep_*; do
      [[ -d "$ep" ]] || continue
      [[ -f "$ep/type" ]] && ep_type=$(<"$ep/type") || ep_type=""
      [[ -f "$ep/direction" ]] && ep_dir=$(<"$ep/direction") || ep_dir=""
      if [[ "${ep_type,,}:${ep_dir,,}" == "interrupt:in" ]]; then
        ((interrupt_in_count += 1))
      fi
    done
  done

  (( interface_count == 1 && hci_interface_count == 0 && vendor_interface_count == 1 && interrupt_in_count == 0 ))
}

capture_transport_role_audit() {
  local usb_dev="$1"
  local base="${USB_SYSFS_ROOT}/${usb_dev}"
  local vid="" pid=""

  [[ -f "$base/idVendor" ]] && vid=$(<"$base/idVendor")
  [[ -f "$base/idProduct" ]] && pid=$(<"$base/idProduct")
  printf 'usb_dev=%s\nvid_pid=%s:%s\n' "$usb_dev" "$vid" "$pid"

  if runtime_transport_is_unproven "$usb_dev"; then
    cat <<'EOF'
transport_role=vendor_runtime_message_interface
hci_transport_proven=no
reset_timeline_safe=no
reason=single ff/ff/ff interface without interrupt-IN matches aic8800_fdrv runtime-message topology, not a source-proven USB HCI interface
EOF
  elif [[ "${pid,,}" == "8d81" && ( "${vid,,}" == "a69c" || "${vid,,}" == "368b" ) ]]; then
    cat <<'EOF'
transport_role=inconclusive_runtime_topology
hci_transport_proven=unknown
reset_timeline_safe=not_assessed
EOF
  else
    cat <<'EOF'
transport_role=loader_or_other_mode
hci_transport_proven=not_applicable
reset_timeline_safe=not_applicable
EOF
  fi
}

capture_firmware_provenance() {
  local installed_dir="/usr/lib/firmware/aic8800D80"
  local repo_dir=""
  local installed repo_file owner

  if [[ -n "$REPO_ROOT" ]]; then
    repo_dir="$REPO_ROOT/src/USB/driver_fw/fw/aic8800D80"
  fi

  printf 'installed_dir=%s\nrepo_dir=%s\n' "$installed_dir" "$repo_dir"
  if [[ ! -d "$installed_dir" ]]; then
    echo 'installed_firmware=missing'
    return 0
  fi

  for installed in "$installed_dir"/*; do
    [[ -f "$installed" ]] || continue
    printf '\n[file %s]\n' "${installed##*/}"
    stat -c 'installed_size=%s' "$installed"
    printf 'installed_sha256='
    sha256sum "$installed" | awk '{print $1}'
    owner=$(pacman -Qo "$installed" 2>/dev/null || true)
    printf 'package_owner=%s\n' "${owner:-unowned}"

    repo_file="$repo_dir/${installed##*/}"
    if [[ -n "$repo_dir" && -f "$repo_file" ]]; then
      stat -c 'repo_size=%s' "$repo_file"
      printf 'repo_sha256='
      sha256sum "$repo_file" | awk '{print $1}'
      if cmp -s "$installed" "$repo_file"; then
        echo 'installed_matches_repo=yes'
      else
        echo 'installed_matches_repo=no'
      fi
    else
      echo 'repo_file=missing'
      echo 'installed_matches_repo=unknown'
    fi
  done
}

capture_d80_profile_assessment() {
  local log_file="${PROFILE_LOG:-$OUT_DIR/dmesg.txt}"
  local line="" chip_id="" chip_mcu_id=""
  local installed_dir="/usr/lib/firmware/aic8800D80"
  local name actual expected mismatches=0 checked=0
  local -A legacy_mcu1_sha256=(
    [fmacfw_8800d80_u02.bin]=1ec680c2b63dcaa0e5d33c5fb6d1857d030f8145c05c385e243760388a61a0da
    [fmacfw_8800d80_u02_ipc.bin]=298c5f05433abb5542c6a9ef30777a7fb2fd6561295497377388fb158ac3a2ef
    [fw_patch_8800d80_u02.bin]=3c5fa5bb678b835adbe42cfe0326074cf8aa5c6d3b93d16d2943b63ad4106b72
    [fw_patch_table_8800d80_u02.bin]=58c07eb4c79de6e6beff683686495dec152688f7de59816cfbe71a0c664ca7c8
    [fw_adid_8800d80_u02.bin]=a526cbd02fcdc495f049f3ad6b5933cb08cd984b16790c716a060d582fee1a56
  )

  if [[ -f "$log_file" ]]; then
    line=$(grep -iE 'chip_id[[:space:]]*=[[:space:]]*(0x)?[0-9a-f]+.*chip_mcu_id[[:space:]]*=[[:space:]]*[0-9]+' "$log_file" | tail -1 || true)
  fi
  printf 'log_file=%s\nsource_line=%s\n' "$log_file" "${line:-not_found}"

  if [[ -n "$line" ]]; then
    chip_id=$(sed -E 's/.*chip_id[[:space:]]*=[[:space:]]*(0x)?([0-9a-fA-F]+).*/\2/' <<<"$line")
    chip_mcu_id=$(sed -E 's/.*chip_mcu_id[[:space:]]*=[[:space:]]*([0-9]+).*/\1/' <<<"$line")
  fi
  printf 'detected_chip_id=%s\ndetected_chip_mcu_id=%s\n' "${chip_id:-unknown}" "${chip_mcu_id:-unknown}"

  if [[ "$chip_id" != "7" || "$chip_mcu_id" != "1" ]]; then
    echo 'recommended_profile=not_assessed'
    echo 'installed_profile_match=not_assessed'
    return 0
  fi

  echo 'recommended_profile=legacy-mcu1'
  echo 'profile_basis=maintained D80 reference maps chip_id=7 chip_mcu_id=1 to matched SDK V3 loader and firmware'
  for name in "${!legacy_mcu1_sha256[@]}"; do
    expected=${legacy_mcu1_sha256[$name]}
    printf '%s_expected_sha256=%s\n' "$name" "$expected"
    if [[ ! -f "$installed_dir/$name" ]]; then
      printf '%s_actual_sha256=missing\n' "$name"
      ((mismatches += 1))
      continue
    fi
    actual=$(sha256sum "$installed_dir/$name" | awk '{print $1}')
    printf '%s_actual_sha256=%s\n' "$name" "$actual"
    ((checked += 1))
    [[ "$actual" == "$expected" ]] || ((mismatches += 1))
  done
  printf 'profile_files_checked=%d\nprofile_file_mismatches=%d\n' "$checked" "$mismatches"
  if (( checked == ${#legacy_mcu1_sha256[@]} && mismatches == 0 )); then
    echo 'installed_profile_match=yes'
  else
    echo 'installed_profile_match=no'
  fi
}

USB_DEV=""
if USB_DEV=$(find_aic_usb_dev); then
  printf '%s\n' "$USB_DEV" >"$OUT_DIR/usb-device.txt"
fi

run_capture uname.txt uname -a
run_capture dkms-status.txt dkms status
run_capture lsusb.txt lsusb
run_capture lsusb-tree.txt lsusb -t
run_capture lsmod.txt lsmod
run_capture pacman-aic-dkms.txt pacman -Qs 'aic|dkms'
run_capture firmware-provenance.txt capture_firmware_provenance
run_capture modules-aic-ko.txt find "/usr/lib/modules/$(uname -r)" -iname '*aic*.ko*' -print
run_capture dev-aicbt-dev.txt bash -c 'if [[ -e /dev/aicbt_dev ]]; then ls -l /dev/aicbt_dev; else echo MISSING /dev/aicbt_dev; fi'
run_capture live-aicbt-params.txt capture_live_aic_params
run_capture aic-zlp-status.txt capture_zlp_status
run_capture rfkill.txt rfkill list
run_capture bluetoothctl-show.txt bluetoothctl show
run_capture_git git-rev-parse-short-head.txt rev-parse --short HEAD
run_capture_git git-branch-current.txt branch --show-current
run_capture_git git-status-short.txt status --short

for module in \
  aic_load_fw \
  aic_load_fw_usb \
  aic8800_fdrv \
  aic8800_fdrv_usb \
  aic_btusb \
  aic_btusb_usb \
  aic_zlp_quirk; do
  run_capture_sudo "modinfo-${module}.txt" modinfo "$module"
done

for module in aic_btusb_usb aic_load_fw aic_zlp_quirk; do
  run_capture_sudo "modinfo-path-${module}.txt" modinfo -k "$(uname -r)" -n "$module"
done

run_capture_sudo hciconfig.txt hciconfig -a
run_capture_sudo btmgmt-info.txt btmgmt info

if [[ -n "$RESET_TIMELINE_MODE" ]]; then
  if [[ -n "$USB_DEV" ]] && runtime_transport_is_unproven "$USB_DEV"; then
    echo "ERROR: refusing --reset-timeline for ${USB_DEV} (D80 runtime)." >&2
    echo "       Its single ff/ff/ff interface has no interrupt-IN endpoint and matches" >&2
    echo "       the aic8800_fdrv runtime-message topology, not a source-proven HCI transport." >&2
    echo "       Run the collector without --reset-timeline to capture the read-only audit." >&2
    exit 3
  fi
  printf '%s\n' "$RESET_TIMELINE_MODE" >"$OUT_DIR/reset-timeline-mode.txt"
  configure_reset_timeline_mode "$RESET_TIMELINE_MODE"
  run_reset_timeline_probe
  capture_reset_window_journal
fi

run_capture_sudo dmesg.txt dmesg -T
run_capture_sudo journal-kernel.txt journalctl -k -b
run_capture d80-profile-assessment.txt capture_d80_profile_assessment

if [[ -n "$USB_DEV" ]]; then
  run_capture usb-sysfs.txt capture_usb_sysfs "$USB_DEV"
  run_capture usb-transport-role-audit.txt capture_transport_role_audit "$USB_DEV"
fi

grep -iE 'diag_reset:|runtime_cmd_tx|CMD TX submit bulk|TX complete|intr_complete|read_data|aic|aic_zlp_quirk|btusb|bluetooth|hci0|0x0c03|firmware|timeout|-110' "$OUT_DIR/dmesg.txt" >"$OUT_DIR/dmesg-filtered.txt" 2>/dev/null || true
grep -iE 'diag_reset:|runtime_cmd_tx|CMD TX submit bulk|TX complete|intr_complete|read_data|aic|aic_zlp_quirk|btusb|bluetooth|hci0|0x0c03|firmware|timeout|-110' "$OUT_DIR/journal-kernel.txt" >"$OUT_DIR/journal-filtered.txt" 2>/dev/null || true

echo "Debug bundle written to: $OUT_DIR"
