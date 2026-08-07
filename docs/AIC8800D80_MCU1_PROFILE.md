# AIC8800D80 MCU1 integration profile

## Outcome

This repository contains a conservative, hardware-validated integration of the profile
that produces working Bluetooth on the test host's physical adapter. The
integration does not replace the existing D80 path globally. It activates only
when both loader observations match:

```text
chip_id == 7
chip_mcu_id == 1
```

All other revisions continue through the existing firmware and patch-table
selection.

## Validated USB result

The complete reference MCU1 loader and firmware set was tested as one coherent
unit before this integration. It changed the runtime presentation from the
failed single-interface `368b:8d81` state to:

| Runtime identity | Interface | Class | Intended owner |
| --- | ---: | --- | --- |
| `a69c:8d81` | 0 | `e0/01/01` | kernel `btusb` |
| `a69c:8d81` | 1 | `e0/01/01` | kernel `btusb` |
| `a69c:8d81` | 2 | `ff/ff/ff` | `aic8800_fdrv` |

That run exposed a working HCI 5.4 controller with successful HCI commands and
no recorded transport errors. It also confirms that the `a69c`/`368b` change is
firmware-state dependent and must not be used alone to infer physical-device or
driver ownership.

## Integration design

The loader now:

1. reads the hardware revision through the existing register path;
2. selects the MCU1 profile only for exact revision `7/1`;
3. reads register `0x40100020`, sets bit 0, and writes it back for the required
   MCU1 Bluetooth-cache fix;
4. loads the matched SDK V3 ADID, base patch, patch table, FMAC, and RF-test
   image as one set;
5. uses the matching legacy patch-table layout and does not mix it with the
   newer patch-buffer-map flow.

The custom `aic_btusb` module has a new `allow_d80_direct_hci` parameter. It is
false by default, causing the module to reject D80 runtime identities and leave
the validated Bluetooth interfaces to the kernel's standard `btusb`. The old
direct-HCI diagnostic route remains available only as an explicit opt-in.

## User-supplied firmware artifacts

The public repository and driver package do not contain these vendor binaries.
A separately generated local firmware package installs them under
`/usr/lib/firmware/aic8800D80/`. Their unique names prevent replacement of the
normal D80 firmware set.

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `fmacfw_8800d80_u02_mcu1.bin` | 327037 | `1ec680c2b63dcaa0e5d33c5fb6d1857d030f8145c05c385e243760388a61a0da` |
| `fw_adid_8800d80_u02_mcu1.bin` | 1708 | `a526cbd02fcdc495f049f3ad6b5933cb08cd984b16790c716a060d582fee1a56` |
| `fw_patch_8800d80_u02_mcu1.bin` | 25300 | `3c5fa5bb678b835adbe42cfe0326074cf8aa5c6d3b93d16d2943b63ad4106b72` |
| `fw_patch_table_8800d80_u02_mcu1.bin` | 984 | `58c07eb4c79de6e6beff683686495dec152688f7de59816cfbe71a0c664ca7c8` |
| `lmacfw_rf_8800d80_u02_mcu1.bin` | 227839 | `964a007438c88b2878461311641803b5891ac32483e090694f4bbc263375986d` |

Provenance: Radxa SDK V3 profile retained by the maintained reference branch
`shenmintao/aic8800d80`, `legacy-mcu1`. The manifest records the exact hashes;
branch names or moving branch heads are not accepted as integrity evidence.

Run the non-invasive check against a user-supplied or installed directory:

```bash
tools/verify_mcu1_profile.sh --source-dir /path/to/aic8800D80
```

Normalize original vendor filenames and create the local package with the tools
documented in `firmware/README.md`. That document also describes the optional,
explicitly acknowledged download from pinned upstream commit
`fffad12a26ba562435783e1be855736e1dec8c1b`. The downloader verifies all five
manifest records and is never used by CI or release automation. Neither a
prepared/fetched directory nor the generated package may be committed or
attached to a public release without redistribution permission.

## Validation status

- Firmware sizes and SHA-256 values: passed.
- `aic_load_fw` and diagnostic `aic_btusb` build on the supported long-term
  kernel variant: passed.
- Both modules build on the tested rolling distribution kernel: passed.
- Firmware-free Arch driver package creation: passed.
- Hash-verified local firmware package creation: passed.
- Historical combined-package persistent installation: passed; the production
  split preserves the same five installed bytes under separate package
  ownership.
- Cold USB-port power-cycle acceptance test: passed.
- Bluetooth discovery: passed for both LE and BR/EDR during the bounded scan.
- Wi-Fi runtime exposure: passed; `wlan0` created by `aic8800_fdrv`.
- Wi-Fi association, WPA2, DHCP, and local traffic: passed on 5 GHz after
  reinitializing the supplicant through `nl80211`.

The first integrated reload exposed a real packaging defect before acceptance:
the separately packaged SDK V3 `aic8800_fdrv` imported five support symbols
that the loader package did not provide. The final package restores the two
flash-status exports and builds the existing RX-buffer preallocation ABI with
`CONFIG_PREALLOC_RX_SKB=y`, matching the proven parent stack. Both installed
kernels were rebuilt after that correction.

Final hardware evidence:

```text
USB lifecycle:  a69c:5721 -> a69c:8d80 -> a69c:8d81
interface 0:    e0/01/01 -> btusb
interface 1:    e0/01/01 -> btusb
interface 2:    ff/ff/ff -> aic8800_fdrv
direct HCI:     allow_d80_direct_hci=N
Bluetooth:      HCI 5.4, UP RUNNING, RX/TX errors=0
Wi-Fi:          phy0 / wlan0 created
Wi-Fi connect:  nl80211, WPA2, DHCP, gateway traffic passed
result:         PASS
```

During the live module replacement, the old `wpa_supplicant` process could
fall back from nl80211 to legacy WEXT. That fallback still allowed scans but
could not call the driver's cfg80211 connect path. Restarting the supplicant
after `wlan0` was fully registered selected nl80211 and made association work.
The acceptance runner now performs and validates that reinitialization.

One transient `device descriptor read/64, error -71` occurred immediately after
the controlled hub-port reconnect. The kernel retried, enumerated the MSC state,
and completed the full lifecycle without a runtime error. It did not affect the
acceptance result but remains worth watching for physical hub/cable reliability.

The preserved acceptance summary is `docs/HARDWARE_VALIDATION.md`.

Future regression tests must continue to verify the full lifecycle rather than
one VID/PID:

```text
a69c:5721 MSC
  -> a69c:8d80 loader
  -> exact MCU1 profile selected and cache fix applied
  -> a69c:8d81 with three interfaces
  -> interfaces 0/1 bound to standard btusb
  -> interface 2 bound to aic8800_fdrv
  -> hci0 responds and can scan
```

Do not repeat the EP1/EP2/H4/EP0 Reset probes on a single `ff/ff/ff`
interface. Those experiments already established the behavior of the mixed
profile and are not an acceptance test for this implementation.
