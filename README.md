# AIC8800D80 MCU1 Linux integration

An Arch-focused integration and hardening project for USB adapters based on the
AICSemi AIC8800D80 MCU1 chipset. These adapters are often sold as generic
**AX900**, **Wi-Fi 6 + Bluetooth 5.4**, or under short-lived retail brand names.

This project is intended for Linux users who can identify their adapter as
AIC8800D80-based but cannot use it with the drivers included in a normal Linux
distribution.

## Relationship to upstream

This is not the original AIC8800 driver project and is not intended to replace
the broader [`shenmintao/aic8800d80`](https://github.com/shenmintao/aic8800d80)
community driver. It complements that project with a firmware-free,
hardware-revision-gated Arch integration for the exact MCU1 profile tested
here.

The production stack deliberately combines components from several owners:

| Component | Production responsibility |
| --- | --- |
| Wi-Fi runtime | `aic8800_fdrv` from a separately reviewed upstream-derived `aic8800d80-dkms` package |
| Firmware loader | This project's hardened, MCU1-gated `aic_load_fw` build |
| Bluetooth HCI | The distribution kernel's standard `btusb` module |
| Bluetooth ACL ZLP compatibility | This project's device-scoped `aic_zlp_quirk` build |
| MCU1 firmware | User-fetched from a pinned upstream commit and verified locally; never redistributed here |

Use the upstream project first for general AIC8800 support, other chip or MCU
revisions, and cross-distribution driver development. Use this project for its
documented Arch/MCU1 installation, firmware boundary, hardening, diagnostics,
and exact hardware-validation scope. See
[upstream relationship and contribution boundaries](docs/UPSTREAM_RELATIONSHIP.md).

> [!IMPORTANT]
> `AX900` is a marketing label, not a chipset identifier. Do not install this
> driver only because AX900 appears on the box or product page.

## Current status

| Function | Status |
| --- | --- |
| USB loader and firmware transition | Working on tested MCU1 adapters |
| Wi-Fi scan, WPA2 association, DHCP and 5 GHz traffic | Working |
| Bluetooth discovery and pairing | Working |
| Bluetooth A2DP audio with SBC and AAC | Working |
| Bluetooth HFP/SCO headset microphone | Not yet validated |
| Secure Boot | Modules must be signed locally or Secure Boot disabled |

Two separately branded physical adapters have passed the complete lifecycle,
Wi-Fi connection, Bluetooth pairing, and sustained AAC playback tests. Both
units contain the same AIC8800D80 MCU1 silicon; this does not imply that every
adapter advertised as AX900 is compatible.

## Check whether your adapter is a candidate

Connect the adapter and run:

```bash
lsusb
```

Known identities during the tested USB lifecycle are:

| USB ID | Meaning |
| --- | --- |
| `a69c:5721` | Initial mass-storage/bootstrap presentation |
| `a69c:8d80` | AIC8800D80 firmware loader |
| `a69c:8d81` | Validated MCU1 Wi-Fi/Bluetooth runtime |
| `368b:8d81` | Another D80 runtime presentation; firmware state matters |

A matching USB ID makes the adapter a candidate, not a guarantee. The loader
must ultimately report both:

```text
chip_id=7
chip_mcu_id=1
```

The setup helper shows detected USB identities. If the revision remains
uncertain, collect logs before forcing firmware:

```bash
sudo journalctl -k -b | grep -iE 'aic|8800|chip_id|mcu_id'
```

See [hardware compatibility](docs/HARDWARE_COMPATIBILITY.md) for the complete
identification rules and tested units.

## Quick start on Arch Linux

Arch Linux is the hardware-validated installation target. Install Git, clone
the repository, and run the guided helper:

```bash
sudo pacman -S --needed git
git clone https://github.com/BTobben/AIC8800D80.git
cd AIC8800D80

tools/aic8800_arch_setup.sh \
  --fetch-mcu1-firmware \
  --acknowledge-upstream-license-status \
  --install
```

The helper:

1. checks Arch Linux, required tools, kernel headers, and visible AIC USB IDs;
2. installs normal build dependencies through `pacman` when needed;
3. downloads the five MCU1 files only after explicit acknowledgement;
4. verifies every firmware size and SHA-256 hash;
5. builds local firmware and DKMS packages outside the Git checkout;
6. displays the package hashes and asks before installation;
7. leaves module reload and USB power cycling to a reboot or manual replug.

The firmware download is pinned to one reviewed upstream commit. Firmware is
never fetched by CI, committed to this repository, or attached to releases.
Use `--firmware-source /path/to/aic8800D80` instead when you already have a
vendor-supplied firmware directory.

Wi-Fi additionally needs the `aic8800_fdrv` runtime module from the separately
maintained [`shenmintao/aic8800d80`](https://github.com/shenmintao/aic8800d80)
driver family. The helper accepts an already installed `aic8800d80-dkms`
package or an explicitly supplied local package through `--wifi-package`. It
does not silently execute a moving AUR PKGBUILD. Bluetooth and loader packaging
can still be built without that optional Wi-Fi dependency, but Wi-Fi will
remain unavailable.

Read the [Arch installation guide](docs/INSTALL_ARCH.md) before using custom
kernel packages, Secure Boot, or a separately built Wi-Fi runtime package.

## Verify after installation

Reboot or unplug and reconnect the adapter, then run:

```bash
lsusb
dkms status
ip link
bluetoothctl list
sudo journalctl -k -b | grep -iE 'aic|btusb|bluetooth|firmware'
```

For a validated MCU1 adapter, the final runtime normally exposes three USB
interfaces:

- interfaces 0 and 1: Bluetooth class `e0/01/01`, owned by standard `btusb`;
- interface 2: vendor class `ff/ff/ff`, owned by `aic8800_fdrv` for Wi-Fi;
- Bluetooth ACL bulk traffic: assisted by the device-scoped `aic_zlp_quirk`.

NetworkManager should use `nl80211`. A stale `wpa_supplicant` process using
legacy WEXT may still show networks but fail to associate.

## Other Linux distributions

The repository retains Debian packaging and its package build is covered by CI,
but physical installation has so far been accepted on Arch Linux only. Users of
Debian, Ubuntu, Fedora, openSUSE, or immutable distributions should treat the
source as an integration reference until distro-specific installation and
uninstallation procedures are validated.

Do not copy a `.ko` file between kernels. DKMS must compile modules for the
exact running kernel and matching headers.

## Firmware and licensing

The five revision-specific MCU1 binaries required by the tested hardware are
not redistributed here because their upstream repository does not provide a
clear redistribution license. This repository contains only filenames, sizes,
hashes, and tools that let the user import or explicitly fetch the original
files for local use.

See [firmware/README.md](firmware/README.md) for offline and manual procedures.

## Known limitations

- Only exact AIC8800D80 MCU1 hardware (`chip_id=7`, `chip_mcu_id=1`) has passed
  the complete acceptance test.
- HFP/SCO call audio and headset microphone input remain unvalidated.
- Full Wi-Fi currently depends on a separately maintained `aic8800_fdrv`
  package; it is not silently downloaded by this project.
- `aic_zlp_quirk` uses kernel kprobes. Kernels without kprobe support cannot
  apply the Bluetooth audio compatibility fix.
- Secure Boot requires locally signed DKMS modules.

## Documentation

- [Arch installation](docs/INSTALL_ARCH.md)
- [Hardware compatibility and identification](docs/HARDWARE_COMPATIBILITY.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [MCU1 firmware profile](docs/AIC8800D80_MCU1_PROFILE.md)
- [Bluetooth audio ZLP fix](docs/AIC8800D80_BLUETOOTH_AUDIO_ZLP.md)
- [Hardware validation record](docs/HARDWARE_VALIDATION.md)
- [Upstream relationship and contribution boundaries](docs/UPSTREAM_RELATIONSHIP.md)
- [Publication privacy boundary](docs/PRIVACY.md)
- [Maintainer and release constraints](docs/MAINTAINER_NOTES.md)

## Project scope

The production path deliberately uses the standard Linux `btusb` driver for
the Bluetooth-class interfaces. This project supplies the D80 loader
integration, revision-gated MCU1 firmware selection, Arch/DKMS packaging,
diagnostics, security hardening, and the device-scoped Bluetooth bulk-transfer
compatibility module. It does not claim independent authorship of the vendor
driver family or general support for every AIC8800 revision.

The code is derived from the public Radxa/AICSemi driver family. Licensing and
attribution for inherited source are documented in `LICENSE`, `src/LICENSE`,
and `debian/copyright`.
