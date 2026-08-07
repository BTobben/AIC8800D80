# AIC8800D80 Bluetooth ACL ZLP compatibility

## Symptom and cause

The revision-gated MCU1 profile exposes a normal Bluetooth controller through
the kernel's standard `btusb` driver, but A2DP playback initially remained
unstable. A test headset paired and connected, then real AAC playback caused:

```text
Bluetooth: hci0: link tx timeout
Bluetooth: hci0: killing stalled connection <headset-address>
spa.bluez5.sink.media: Missing completion reports for packet
```

SBC was noticeably more stable than AAC. Linux was not losing the pairing;
the controller stopped returning the completion flow needed for outstanding ACL
packets, after which the HCI core deliberately killed the stalled connection.

The missing transport detail is a USB zero-length packet (ZLP) flag on
Bluetooth ACL bulk OUT URBs. The repository's vendor `aic_btusb` transport
already sets `URB_ZERO_PACKET` for every ACL bulk OUT submission, while the
generic kernel `btusb` allocation path does not. The maintained MCU1 reference
independently validated the same AAC-versus-SBC failure on `368b:8d81`: adding
the flag kept AAC connected for more than one hour. See
[shenmintao/aic8800d80 issue #63](https://github.com/shenmintao/aic8800d80/issues/63).

## Implementation

`aic_zlp_quirk` is a companion module; it does not replace or rebind the
distribution's `btusb` driver. It attaches to `btusb:alloc_bulk_urb` and adds
only `URB_ZERO_PACKET`. If that private helper is unavailable, it can attach to
`usb_submit_urb`, but that fallback changes an URB only when all of these checks
pass:

- VID:PID is exactly `a69c:8d81` or `368b:8d81`;
- the transfer is bulk OUT;
- the endpoint belongs to Bluetooth interface 0;
- interface 0 is class/subclass/protocol `e0/01/01`.

The two IDs cover the D80 runtime identities represented in this repository.
The `a69c:8d81` inclusion is additionally backed by the vendor `aic_btusb`
device table, its unconditional ACL `URB_ZERO_PACKET` behavior, the measured
Bluetooth-class descriptor, and the reproduced live failure. Loader, Wi-Fi,
isochronous SCO, and unrelated USB transfers are not modified.

The module exposes read-only runtime evidence:

```text
/sys/module/aic_zlp_quirk/parameters/hook
/sys/module/aic_zlp_quirk/parameters/injections
```

## Hardware validation

The candidate module was loaded without disconnecting or rebinding the active
`a69c:8d81` device. It attached through the preferred
`btusb:alloc_bulk_urb` hook. The hardware tester then played normal streaming
audio through the test headset using A2DP AAC for a bounded acceptance window.

Result:

```text
active profile:       A2DP AAC
duration:             bounded acceptance window
connection:           remained connected
modified ACL URBs:    increased throughout playback
HCI RX/TX errors:     no new errors
new link tx timeouts: 0
new killed links:     0
missing completions:  0
transport terminations: 0
```

Before loading the module, the same real AAC use disconnected within seconds
to roughly one minute and repeatedly produced the completion and kernel timeout
messages above. The five-minute result therefore verifies a material hardware
effect, not merely a successful module load.

### Second physical adapter

A separately sourced adapter was validated sequentially on the same host after
unplugging the first adapter. It exposed the same MCU1 hardware and USB
lifecycle:

```text
a69c:5721 MSC/bootstrap -> a69c:8d80 loader -> a69c:8d81 runtime
chip_id=7, chip_mcu_id=1
Bluetooth interfaces 0/1: btusb
Wi-Fi interface 2:      aic8800_fdrv
```

The installed MCU1 profile loaded the coherent `_mcu1` firmware set. Wi-Fi
associated on 5 GHz, received a network configuration, and passed local gateway
traffic. Bluetooth discovery completed without HCI errors. The
The test headset then paired and streamed desktop audio through A2DP AAC.
During the captured run the ZLP injection count increased continuously, the
connection remained active, HCI RX/TX errors remained zero, and no new link timeout,
stalled-link, missing-completion, or BlueZ transport-termination message was
recorded.

This confirms that the device-scoped ZLP fix and the MCU1 loader/runtime stack
are not limited to the first retail enclosure tested.

This validation covers A2DP ACL traffic. Earlier HFP/SCO testing also produced
corrupted SCO packets; the ZLP module intentionally does not change
isochronous transfers, so headset microphone/call-profile stability remains a
separate follow-up.

## Verification

Standard `btusb` must continue to own interfaces 0/1. Check the live hook and
counter during A2DP traffic with:

```bash
lsusb -t
cat /sys/module/aic_zlp_quirk/parameters/hook
cat /sys/module/aic_zlp_quirk/parameters/injections
```

The normal debug collector also records these fields in
`aic-zlp-status.txt`. To roll back a live test without replacing any other
driver, stop Bluetooth audio and run:

```bash
sudo rmmod aic_zlp_quirk
```
