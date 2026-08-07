#!/usr/bin/env bash
set -u

if (( EUID != 0 )); then
    echo "ERROR: run through sudo or pkexec"
    exit 2
fi

profile=${1:-}
target_bssid=${2:-}
target_band=${3:-}
target_channel=${4:-}
if [[ -z "$profile" ]]; then
    echo "Usage: $0 SAVED_PROFILE [BSSID [BAND [CHANNEL]]]"
    echo "The optional BSSID arguments create a temporary pinned clone."
    exit 3
fi

started=$(date '+%F %T')
echo "started=$started"
echo "profile=$profile"
ssid=$(nmcli -g 802-11-wireless.ssid connection show "$profile")

if nmcli -t -f DEVICE,TYPE device status 2>/dev/null \
    | grep -q '^p2p-dev-wlan0:wifi-p2p$'; then
    echo "wifi_backend=nl80211"
else
    echo "WARNING: nl80211 P2P companion is absent; WEXT fallback is possible"
fi

# Deliberately omit PSK/secret fields.
nmcli -f \
connection.id,802-11-wireless.ssid,802-11-wireless.band,802-11-wireless.channel,802-11-wireless.bssid,802-11-wireless.cloned-mac-address,802-11-wireless.mac-address-randomization,802-11-wireless-security.key-mgmt,802-11-wireless-security.proto,802-11-wireless-security.pairwise,802-11-wireless-security.group,802-11-wireless-security.pmf \
connection show "$profile"

wpa_cli -i wlan0 log_level DEBUG
restore_log_level() {
    wpa_cli -i wlan0 log_level INFO >/dev/null 2>&1 || true
    if [[ -n "${debug_profile:-}" ]]; then
        nmcli connection delete "$debug_profile" >/dev/null 2>&1 || true
    fi
}
trap restore_log_level EXIT

active_profile=$profile
if [[ -n "$target_bssid" ]]; then
    debug_profile="AIC8800 temporary pinned test"
    nmcli connection delete "$debug_profile" >/dev/null 2>&1 || true
    nmcli connection clone "$profile" "$debug_profile"
    nmcli connection modify "$debug_profile" \
        connection.autoconnect no \
        802-11-wireless.bssid "$target_bssid" \
        802-11-wireless.cloned-mac-address permanent
    if [[ -n "$target_band" ]]; then
        nmcli connection modify "$debug_profile" 802-11-wireless.band "$target_band"
    fi
    if [[ -n "$target_channel" ]]; then
        nmcli connection modify "$debug_profile" 802-11-wireless.channel "$target_channel"
    fi
    active_profile=$debug_profile
    echo "temporary_profile=$debug_profile bssid=$target_bssid band=$target_band channel=$target_channel"
fi

nmcli device disconnect wlan0 >/dev/null 2>&1 || true
sleep 2
# Do not force an extra scan here. NetworkManager may already have one in
# flight after the disconnect; overlapping it used to trigger the vendor
# driver's harmless but noisy "scan_request is NULL" completion path. The
# connection activation below requests any scan it actually needs.
nmcli -f SSID,BSSID,CHAN,FREQ,SIGNAL,SECURITY device wifi list \
    --rescan no ifname wlan0 \
    | grep -F "$ssid" || true

nmcli -w 40 connection up id "$active_profile" ifname wlan0
connect_status=$?
echo "connect_status=$connect_status"
iw dev wlan0 link || true

echo "== debug supplicant =="
journalctl -u wpa_supplicant --since "$started" --no-pager \
    | grep -Ei 'wlan0|nl80211|connect|assoc|auth|reject|fail|error|errno|SME|CTRL-EVENT' \
    | tail -450 || true

echo "== exact kernel window =="
journalctl -k --since "$started" --no-pager \
    | grep -Ei 'aic|rwnx|wlan0|connect|assoc|auth|fail|error|invalid|busy' \
    | tail -350 || true

exit 0
