# Upstream relationship

## Project roles

The broader community driver is maintained at
[`shenmintao/aic8800d80`](https://github.com/shenmintao/aic8800d80). It carries
the complete Wi-Fi runtime driver, firmware loader, firmware collections,
multi-distribution installation support, and support for more AIC8800 hardware
than this repository claims.

This repository is a focused integration rather than a competing general
driver. Its accepted production profile is limited to AIC8800D80 hardware that
reports:

```text
chip_id=7
chip_mcu_id=1
```

The maintained local value is:

- an Arch-oriented, package-managed installation and rollback path;
- exact MCU1 revision gating with no unsafe fallback to another firmware set;
- a firmware-free public repository and hash-verified local firmware import;
- hardened loader, USB-response, and patch-table input boundaries;
- device-scoped Bluetooth ACL ZLP compatibility while retaining kernel
  `btusb` ownership;
- privacy-aware diagnostics, public-history auditing, and reproducible release
  checks;
- a hardware-validation record for two independently sourced adapters.

## Source and runtime lineage

The source tree descends from the public Radxa/AICSemi driver family. The
tested Wi-Fi module, `aic8800_fdrv`, is supplied separately by an
upstream-derived `aic8800d80-dkms` package. This repository supplies the
tested MCU1 loader and ZLP compatibility builds, while Bluetooth controller
ownership remains with the distribution kernel's `btusb` module.

The five required MCU1 firmware files originate from the upstream
[`legacy-mcu1`](https://github.com/shenmintao/aic8800d80/tree/legacy-mcu1)
branch. The opt-in fetcher never follows that moving branch: it downloads from
the immutable reviewed commit recorded in
`tools/aic8800_fetch_mcu1_firmware.sh`, then verifies filenames, sizes, and
SHA-256 hashes. The files are not committed, cached by CI, or attached to this
project's releases because upstream provides no clear redistribution license
for that firmware set.

## Shared Bluetooth finding

The upstream community independently isolated the Bluetooth audio failure as
a missing USB zero-length-packet behavior and validated the `368b:8d81` fix in
[`issue #63`](https://github.com/shenmintao/aic8800d80/issues/63). That work is
explicitly credited here and is foundational evidence for the production
design.

This repository additionally scopes its ZLP compatibility module to
`a69c:8d81`, based on the vendor transport behavior, matching Bluetooth
descriptors, reproduced failure, increasing live injection counter, and local
hardware A/B tests. This broader match remains part of this project's current
MCU1 validation scope; it should be proposed upstream only with the longer
cold-boot AAC and concurrent Wi-Fi evidence requested by upstream maintainers.

## Where changes should go

Changes with general value should be offered upstream after local validation,
especially:

- memory-safety hardening that applies to the common loader;
- kernel compatibility fixes;
- support for additional chip or MCU revisions;
- broadly reproduced Wi-Fi or Bluetooth transport corrections.

Changes may remain integration-specific here when they concern:

- Arch package orchestration and conservative installation policy;
- the no-redistribution firmware workflow;
- exact MCU1 acceptance gates and diagnostics;
- public-release privacy and provenance enforcement.

Bug reports must identify the responsible component. Wi-Fi runtime defects in
`aic8800_fdrv` normally belong upstream. Problems in this repository's setup
tools, MCU1 loader modifications, firmware verification, or ZLP extension
belong here. Standard `btusb`, BlueZ, PipeWire, and NetworkManager issues should
not be attributed to either driver project without component-level evidence.
