# Arch Linux installation

This is the hardware-validated installation path for AIC8800D80 MCU1 USB
Wi-Fi/Bluetooth adapters.

## Before installing

Confirm that at least one candidate identity is visible:

```bash
lsusb | grep -Ei 'a69c:(5721|8d80|8d81)|368b:8d81'
```

The retail name `AX900` is not sufficient. The complete tested profile requires
loader values `chip_id=7` and `chip_mcu_id=1`.

Install the headers for the running kernel. Examples:

```bash
sudo pacman -S --needed base-devel dkms git curl linux-headers
```

For the LTS kernel, use `linux-lts-headers`; custom kernels require their own
matching header package. The setup helper detects the owning kernel package and
offers its corresponding `-headers` package when possible.

## Guided installation

Clone the public repository:

```bash
git clone https://github.com/BTobben/AIC8800D80.git
cd AIC8800D80
```

Fetch the reviewed MCU1 firmware set, build both local packages, and install
them:

```bash
tools/aic8800_arch_setup.sh \
  --fetch-mcu1-firmware \
  --acknowledge-upstream-license-status \
  --install
```

The script remains interactive before package installation. Add `--yes` only
for a controlled, non-interactive run.

If the five vendor files were obtained separately, keep them outside the Git
checkout and use:

```bash
tools/aic8800_arch_setup.sh \
  --firmware-source /path/to/vendor/aic8800D80 \
  --install
```

Use `--build-only` to create packages without installing them. The output path
is printed at the end and retained automatically.

## Wi-Fi runtime dependency

The package in this repository provides:

- `aic_load_fw`, including exact MCU1 revision selection;
- diagnostic `aic_btusb_usb`, disabled for normal D80 direct-HCI ownership;
- `aic_zlp_quirk`, scoped to the supported Bluetooth bulk endpoint behavior.

The vendor runtime interface used for Wi-Fi is owned by `aic8800_fdrv`. That
module currently comes from the separately maintained `aic8800d80-dkms`
package used during hardware acceptance.

The setup helper behaves conservatively:

- if `aic8800d80-dkms` is already installed, it records the installed version;
- if you have a reviewed local package, pass
  `--wifi-package /path/to/aic8800d80-dkms.pkg.tar.zst`;
- if neither is available, loader and Bluetooth packages can still be built,
  but the script warns that Wi-Fi cannot come up.

It intentionally does not clone and execute the current AUR recipe without
review. That recipe follows a moving upstream branch and installs overlapping
loader and firmware content, which is unsuitable for an unattended production
path.

## What installation changes

The helper installs ordinary Arch packages through `pacman`:

- `aic8800-mcu1-firmware-local`: five hash-verified `_mcu1` files under
  `/usr/lib/firmware/aic8800D80/`;
- `aic8800-usb-dkms`: DKMS source for the loader, diagnostic Bluetooth module,
  and ZLP compatibility module;
- optionally, the user-supplied `aic8800d80-dkms` Wi-Fi package.

It does not unload active modules, reset USB ports, restart networking, or
power-cycle the adapter. Rebooting is the simplest way to activate the new
module and firmware set consistently.

## Verification

After reboot or replug:

```bash
pacman -Q aic8800-usb-dkms aic8800-mcu1-firmware-local
pacman -Q aic8800d80-dkms  # required for Wi-Fi
dkms status
modinfo aic_load_fw
modinfo aic_zlp_quirk
lsusb -t
ip link
bluetoothctl list
```

Expected final USB topology for the tested profile:

```text
a69c:8d81
  interface 0 e0/01/01 -> btusb
  interface 1 e0/01/01 -> btusb
  interface 2 ff/ff/ff -> aic8800_fdrv
```

Check the installed firmware without changing hardware state:

```bash
tools/verify_mcu1_profile.sh --source-dir /usr/lib/firmware/aic8800D80
```

## Manual package build

Firmware package:

```bash
tools/aic8800_fetch_mcu1_firmware.sh \
  --output-dir /tmp/aic8800-mcu1 \
  --acknowledge-upstream-license-status

tools/aic8800_build_mcu1_firmware_package.sh \
  --source-dir /tmp/aic8800-mcu1 \
  --output-dir /tmp/aic8800-packages
```

Driver package from the current checkout:

```bash
cd packaging/arch/aic8800-usb-dkms
AIC8800_REPO_URL="file://$(git -C ../../.. rev-parse --show-toplevel)" \
  AIC8800_REPO_REF="$(git -C ../../.. branch --show-current)" \
  makepkg -Csf
```

## Updating and uninstalling

After pulling a new release, rerun the setup helper. DKMS rebuilds registered
modules for later kernel updates when matching headers are installed.

Remove project-owned packages with:

```bash
sudo pacman -Rns aic8800-usb-dkms aic8800-mcu1-firmware-local
```

Remove a separately supplied Wi-Fi package only if no other device needs it:

```bash
sudo pacman -Rns aic8800d80-dkms
```

## Secure Boot

Secure Boot commonly blocks unsigned out-of-tree modules. This project does
not disable Secure Boot or manage private signing keys. Sign the DKMS modules
using your distribution's documented procedure, or disable Secure Boot in
firmware settings if that is acceptable for your system.
