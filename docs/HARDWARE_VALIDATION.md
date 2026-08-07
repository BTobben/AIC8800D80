# Hardware validation

## Accepted profile

The complete integration test passed on two independently sourced USB adapters
with the exact loader-reported profile:

```text
chip_id=7
chip_mcu_id=1
```

Retail branding and enclosure details are intentionally omitted. They are not
reliable hardware identifiers and are unnecessary for reproducing the result.

## Loader and runtime lifecycle

Both adapters completed the expected lifecycle:

```text
a69c:5721  bootstrap / mass storage
    -> a69c:8d80  firmware loader
    -> a69c:8d81  three-interface runtime
```

The loader selected the complete, hash-verified MCU1 firmware profile and
applied the MCU1 Bluetooth cache correction. Runtime ownership was:

```text
interface 0: e0/01/01 -> standard btusb
interface 1: e0/01/01 -> standard btusb
interface 2: ff/ff/ff -> aic8800_fdrv
direct diagnostic HCI ownership: disabled
```

The same installed stack accepted a sequential swap between the two physical
adapters without manual rebinding or configuration changes.

## Bluetooth acceptance

The standard kernel Bluetooth path passed:

- controller enumeration as HCI 5.4;
- bidirectional HCI command/event traffic;
- LE and BR/EDR discovery;
- pairing and A2DP playback;
- sustained SBC and AAC playback with the device-scoped ZLP compatibility
  module active;
- sequential operation with both physical adapters.

The headset model and controller addresses are intentionally not recorded.
HFP/SCO call audio and microphone input remain outside the accepted scope.

## Wi-Fi acceptance

The vendor runtime interface passed:

- `aic8800_fdrv` initialization and managed-interface creation;
- NetworkManager operation through `nl80211`;
- WPA2 association on 5 GHz;
- DHCP configuration;
- local gateway traffic;
- sequential operation with both physical adapters.

No SSID, password, IP address, MAC address, hostname, or other network-specific
value is retained in this repository.

## Build and packaging acceptance

The loader, diagnostic Bluetooth module, and ZLP compatibility module built and
installed through DKMS on both a rolling distribution kernel and its supported
long-term kernel variant. Exact host kernel patch levels are intentionally not
published because they are not required to select compatible hardware.

The production packaging keeps the five MCU1 files outside Git. Local import or
explicit fetch verifies every filename, size, and SHA-256 value before package
creation. CI does not fetch or publish this MCU1 firmware set.

## Reproduction criteria

A future acceptance run must verify the full lifecycle, not one VID/PID:

```text
a69c:5721 bootstrap
  -> a69c:8d80 loader
  -> exact chip_id=7 / chip_mcu_id=1 profile
  -> hash-verified MCU1 firmware and cache correction
  -> a69c:8d81 three-interface runtime
  -> interfaces 0/1 owned by standard btusb
  -> interface 2 owned by aic8800_fdrv
  -> Bluetooth discovery and sustained A2DP
  -> Wi-Fi association, DHCP, and traffic
```

Diagnostic bundles must be reviewed before publication and stripped of network
names, addresses, serial numbers, usernames, hostnames, absolute home paths,
and unrelated system information.
