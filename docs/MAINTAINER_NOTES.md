# Maintainer notes

This page contains release constraints that should not distract from the user
installation guide.

## Release checks

Before merging or publishing packages:

```bash
tools/check_public_release.sh --tree --history
```

Required CI checks are:

- driver and Debian package build;
- documentation build;
- publication-tree audit;
- complete reachable-history audit.

The release job runs only after an explicit manual workflow dispatch. A push to
`main`, repository visibility change, or pull-request merge must never publish
packages or create a release automatically.

The public Git history must use the maintainer's GitHub noreply address. Never
mirror or graft history from a private development repository.

The complete privacy boundary is documented in [PRIVACY.md](PRIVACY.md).

## Firmware boundary

The five MCU1 files listed in `firmware/aic8800d80-mcu1.manifest` are not
redistributed. Four are unique to a maintained reference branch that publishes
no explicit LICENSE or COPYING file. Public availability is not by itself a
redistribution license.

Allowed project artifacts include:

- hashes, sizes, and original/installed filenames;
- a user-invoked downloader pinned to the reviewed upstream commit;
- local preparation and package-building tools;
- firmware-free driver packages.

Do not invoke the firmware downloader from CI, cache its output, or upload a
locally generated firmware package to a release without permission.

The inherited Radxa source tree contains an older firmware collection covered
by its published `src/*` GPL-2 declaration. This project makes no new licensing
claim about those inherited files.

## Wi-Fi dependency boundary

The currently validated Wi-Fi interface requires `aic8800_fdrv` from a separate
maintained `aic8800d80-dkms` package. Do not silently run a moving AUR recipe or
replace that dependency with the older in-tree copy until compatibility changes
have been imported, reviewed, and tested against supported kernels.

The guided installer may accept an explicitly supplied local Wi-Fi package and
must verify its package name before installation.

## Publication snapshot tool

`tools/aic8800_create_public_snapshot.sh` exists for maintainers who need a new
history-free repository. It exports the committed tree, force-adds only those
exported tracked files, compares the complete file manifest, creates one
noreply-authored commit, and runs both audits.

Never copy `.git`, use a mirror push, or upload ignored build directories and
local firmware output blindly.

## Hardware acceptance

The automated package build does not replace physical acceptance. A release
claiming the validated MCU1 profile should confirm:

```text
a69c:5721 -> a69c:8d80 -> a69c:8d81
interfaces 0/1 -> standard btusb
interface 2 -> aic8800_fdrv
Bluetooth discovery and sustained A2DP audio
Wi-Fi association, DHCP, and traffic
```

HFP/SCO remains a documented limitation until separately accepted.
