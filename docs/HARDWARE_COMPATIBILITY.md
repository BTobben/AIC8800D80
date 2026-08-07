# Hardware compatibility

## What is actually supported

The accepted hardware profile is AICSemi AIC8800D80 with:

```text
chip_id=7
chip_mcu_id=1
```

Two independently sourced physical USB adapters passed the same test suite.
Both contained this exact MCU1 revision.

| Tested unit | Bluetooth | Wi-Fi | Sustained AAC audio |
| --- | --- | --- | --- |
| MCU1 adapter A | Passed | Passed | Passed |
| MCU1 adapter B | Passed | Passed | Passed |

Retail branding, enclosure shape, antenna count, and the term AX900 can change
without notice. They are not safe firmware selectors.

## USB identities are states, not product guarantees

One physical adapter can expose several identities as firmware starts:

```text
a69c:5721  bootstrap / mass storage
    -> a69c:8d80  loader
    -> a69c:8d81  validated MCU1 runtime
```

Historical or mismatched firmware can instead produce `368b:8d81`. A VID/PID
change therefore does not prove that a different physical device was connected.

Candidate identities recognised by the project are:

```text
a69c:5721
a69c:8d80
a69c:8d81
368b:8d81
```

## How to identify the chipset

Start with:

```bash
lsusb
sudo journalctl -k -b | grep -iE 'aic|8800|chip_id|mcu_id'
```

Useful descriptor details:

```bash
sudo lsusb -v -d a69c:8d80
sudo lsusb -v -d a69c:8d81
sudo lsusb -v -d 368b:8d81
```

Do not run all three commands blindly with `set -e`; only the currently active
identity exists.

The setup helper reports visible candidate IDs but cannot prove the MCU
revision before the loader has read it. If logs never establish revision `7/1`,
do not force the MCU1 firmware profile.

## Expected runtime ownership

The working `a69c:8d81` presentation exposes:

| Interface | Class | Linux owner | Role |
| ---: | --- | --- | --- |
| 0 | `e0/01/01` | standard `btusb` | Bluetooth HCI |
| 1 | `e0/01/01` | standard `btusb` | Bluetooth companion interface |
| 2 | `ff/ff/ff` | `aic8800_fdrv` | Wi-Fi/runtime messages |

A single vendor-specific `ff/ff/ff` interface must not be forced onto `btusb`.
That topology was observed with a mismatched firmware profile and did not
produce a working HCI controller.

## Reporting another adapter

When reporting success or failure, include:

- retail brand and product link if available;
- all observed USB IDs;
- `chip_id` and `chip_mcu_id` loader lines;
- `lsusb -t` after runtime enumeration;
- kernel version and distribution;
- `dkms status`;
- whether Wi-Fi association, Bluetooth pairing, and audio streaming were each
  tested independently.

Remove SSIDs, public/private IP addresses, MAC addresses, hostnames, and other
personal information before posting logs.
