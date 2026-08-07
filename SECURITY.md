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
