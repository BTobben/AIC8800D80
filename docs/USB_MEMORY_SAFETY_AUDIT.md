# USB memory-safety review

This review covers the three kernel modules built and distributed by the Linux
USB package:

- `aic_load_fw`, including its USB receive path and firmware command handling;
- `aic_btusb`, in both normal and diagnostic configurations;
- `aic_zlp_quirk`.

Historical Android, SDIO, PCIe, and platform-patch copies are reference source,
not part of this supported build scope.

## Reviewed input boundaries

The review concentrated on data that can cross a trust boundary:

- writes and ioctls through the Bluetooth character device;
- USB frames and firmware confirmations received from the controller;
- firmware patch tables and derived filenames;
- fixed-size command and memory-transfer buffers.

The active paths now reject truncated frames, inconsistent embedded lengths,
oversized memory writes, invalid task/index values, undersized patch records,
and out-of-range patch-table indexes before copying or dispatching data.
Destinations for controller confirmations are length-bounded. Patch-table
strings are explicitly terminated, generated firmware filenames are checked
for truncation, and allocation failures follow defined cleanup paths.

The supported module directories no longer use the unbounded string-copy and
formatting functions checked by `tools/check_usb_memory_safety.sh`.

## Validation

The maintained modules were rebuilt with the kernel warning level enabled and
additional compiler checks for format strings, array bounds, string overflow,
and string truncation. Both the normal and diagnostic Bluetooth builds were
covered. A compiler static analyzer was also run over the loader and diagnostic
Bluetooth compilation units after filtering generated kernel-module metadata;
it reported no remaining security findings in this scope.

CI runs the active-source policy check on every pull request and publication
audit. This is a targeted review and regression barrier, not a formal proof of
memory safety. Security reports remain welcome through the private process in
`SECURITY.md`.
