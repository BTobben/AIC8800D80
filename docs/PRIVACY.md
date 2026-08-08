# Publication privacy boundary

This repository is published from a new, history-free snapshot. Private
development commits are never mirrored, grafted, or force-pushed into the
public repository.

## Maintainer identity

The only intended maintainer identity is the public GitHub account `BTobben`
and its GitHub-provided noreply address. A personal mailbox address, workstation
username, hostname, home directory, or local application path must not appear
in the publication tree, Git metadata, CI logs, or generated package metadata.

## Test evidence

Hardware evidence is limited to compatibility-relevant values:

- USB VID:PID lifecycle;
- loader-reported chip and MCU revision;
- USB interface classes and driver ownership;
- functional pass/fail results.

The published documentation intentionally omits retail order links, controller
addresses, network names and addresses, hostnames, exact host kernel patch
levels, headset models, and timestamped local bundle names.

## Inherited source attribution

The vendor-derived source tree retains original copyright, author,
signed-off-by, OWNERS, and maintainer information where required for source
provenance and licensing. These third-party identities and historical upstream
build examples are not data from the project maintainer's workstation.

Do not mechanically remove inherited attribution without a separate licensing
review. The publication audit instead distinguishes upstream source provenance
from project-owned documentation, packaging, workflows, and tools.

The complete source tree is nevertheless checked for high-confidence secrets,
shared Android Bluetooth addresses, enabled experimental network snooping, and
new workstation or personal-mail identities. Three exact legacy vendor
identity exceptions are kept in the audit itself for inherited source
attribution and build examples. Adding another identity causes the audit to
fail.

## Before every public push

Run:

```bash
tools/check_public_release.sh --tree --history
```

For a brand-new public repository, use
`tools/aic8800_create_public_snapshot.sh`. It exports only the committed tree,
creates a new root commit with the GitHub account identity, compares the entire
file manifest, and runs both audits before returning the snapshot.
