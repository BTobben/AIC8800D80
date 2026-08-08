# Security policy

## Reporting a vulnerability

Please report security issues through GitHub's private security-advisory
feature. Do not include credentials, Wi-Fi passphrases, full diagnostic bundles,
or unredacted hardware identifiers in a public issue.

For driver problems that are not security-sensitive, open a normal issue with:

- kernel and distribution versions;
- the adapter's USB VID:PID and interface layout;
- relevant module versions and non-secret parameters;
- a short, time-bounded kernel log with MAC addresses, hostnames, SSIDs, serial
  numbers, IP addresses, and user paths redacted.

The diagnostic collector may capture system metadata. Review every generated
bundle before sharing it publicly.

## Supported code

Security fixes target the latest code on the repository's maintained branch.
Historical diagnostic branches and opt-in experimental transports are not
production support surfaces.

The maintained Linux USB package builds only `aic_btusb`, `aic_load_fw`, and
`aic_zlp_quirk`. Historical Android platform patches are retained as source
references. In particular, `aic_btsnoop_net.c` is an unfinished, disabled-by-
default network-debug prototype and must not be enabled in production builds.
Its fixed private-network endpoints are historical vendor lab settings, not
supported defaults.

Products integrating the historical Android templates must obtain a unique
Bluetooth address from controller OTP/eFuse or provision one per device. The
repository deliberately provides no shared `persist.service.bdroid.bdaddr`
value.

The latest targeted review of the supported USB input boundaries, its scope,
validation, and limitations are documented in
[`docs/USB_MEMORY_SAFETY_AUDIT.md`](docs/USB_MEMORY_SAFETY_AUDIT.md).
