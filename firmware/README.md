# AIC8800D80 MCU1 firmware

The tested `chip_id=7`, `chip_mcu_id=1` hardware needs five revision-specific
vendor binaries. This project does not redistribute them because their upstream
repository does not provide a clear redistribution license.

The project records the expected vendor filenames, installed `_mcu1` names,
sizes, and SHA-256 hashes in
[`aic8800d80-mcu1.manifest`](aic8800d80-mcu1.manifest).

## Guided Arch Linux route

The shortest supported route fetches from one immutable upstream commit,
verifies all five files, builds a local package, and asks before installation:

```bash
tools/aic8800_arch_setup.sh \
  --fetch-mcu1-firmware \
  --acknowledge-upstream-license-status \
  --install
```

The acknowledgement confirms that you have seen the missing redistribution
license warning; it does not grant new rights. The downloaded files remain
local and are never used by CI or release automation.

## Existing vendor firmware

Keep the source directory outside the Git checkout. The helper accepts both
original vendor names and already normalized `_mcu1` names:

```bash
tools/aic8800_arch_setup.sh \
  --firmware-source /path/to/vendor/aic8800D80 \
  --install
```

Verify without building or installing:

```bash
tools/verify_mcu1_profile.sh --source-dir /path/to/vendor/aic8800D80
```

## Manual offline preparation

Normalize a verified source directory:

```bash
tools/aic8800_prepare_mcu1_firmware.sh \
  --source-dir /path/to/vendor/aic8800D80 \
  --output-dir /tmp/aic8800-mcu1-prepared
```

Build a local Arch package:

```bash
tools/aic8800_build_mcu1_firmware_package.sh \
  --source-dir /tmp/aic8800-mcu1-prepared \
  --output-dir /tmp/aic8800-mcu1-package
```

Install the resulting package with `sudo pacman -U` after reviewing its path
and SHA-256 value.

## Direct opt-in fetch

The lower-level fetcher is available when package construction is handled
separately:

```bash
tools/aic8800_fetch_mcu1_firmware.sh \
  --output-dir /tmp/aic8800-mcu1-fetched \
  --acknowledge-upstream-license-status
```

It never follows `main` or the moving `legacy-mcu1` branch. A size or hash
mismatch rejects and removes the complete temporary download.

Do not commit, mirror, cache in public CI, or attach downloaded/generated
firmware to a release without permission from the rights holder.
