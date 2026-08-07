# Troubleshooting

## The adapter still appears as mass storage

If `lsusb` shows `a69c:5721`, the device has not completed the bootstrap to the
loader. Confirm the DKMS modules and matching kernel headers are installed:

```bash
dkms status
modinfo aic_load_fw
sudo journalctl -k -b | grep -iE 'aic|5721|8d80|firmware'
```

Reboot once after package installation. Avoid repeatedly authorizing and
deauthorizing an uncertain USB sysfs path.

## Firmware files are missing or rejected

Verify the exact local profile:

```bash
tools/verify_mcu1_profile.sh --source-dir /usr/lib/firmware/aic8800D80
```

All five `_mcu1` files must match the manifest. Do not combine files from
different vendor releases.

## Bluetooth discovery works but audio disconnects

Check whether the device-scoped bulk-transfer helper is loaded:

```bash
modinfo aic_zlp_quirk
lsmod | grep aic_zlp_quirk
sudo journalctl -k -b | grep -iE 'aic_zlp_quirk|btusb|Bluetooth|hci'
```

When available, its counters are under:

```text
/sys/module/aic_zlp_quirk/parameters/
```

Kernels without kprobe support cannot attach this compatibility module. Secure
Boot can also prevent it from loading.

## Wi-Fi sees networks but will not connect

First confirm the runtime module and cfg80211 interface:

```bash
lsmod | grep aic8800_fdrv
iw dev
sudo journalctl -u NetworkManager -b | grep -iE 'nl80211|wext|wlan'
```

The tested connection path uses `nl80211`. A supplicant process started before
the live driver replacement may retain a legacy WEXT fallback. Rebooting is the
safest recovery after installation. Advanced users can restart NetworkManager
after `wlan0` is fully registered.

## DKMS build fails

The running kernel and headers must match:

```bash
uname -r
test -r "/usr/lib/modules/$(uname -r)/build/Makefile" && echo headers-present
dkms status
```

For standard Arch kernels, install the corresponding package, for example
`linux-headers` or `linux-lts-headers`. Custom kernel users need that kernel's
own headers.

Do not copy a module built for another kernel. `modinfo` must report vermagic
compatible with `uname -r`.

## Secure Boot blocks modules

Look for signature failures:

```bash
sudo journalctl -k -b | grep -iE 'verification failed|unsigned|secure boot|lockdown'
```

Sign the DKMS modules locally or disable Secure Boot. Never upload or share a
private module-signing key.

## Collect a diagnostic bundle

The diagnostic collector records driver provenance, USB topology, firmware
hashes, and scoped kernel logs:

```bash
sudo tools/aic_bt_collect_debug.sh /tmp/aic8800-debug
```

Review every file before sharing it. Remove network names, addresses, device
MACs, usernames, hostnames, and unrelated logs.

Historical direct-HCI experiments are not normal installation steps and should
not be repeated on an unknown device. Open a diagnostic issue with a reviewed,
sanitized collector bundle instead.
