# Homebrew public-inbox

This Homebrew tap installs [public-inbox](https://public-inbox.org/) and its
`lei` command-line tool on macOS. Linux provides a second test platform.

## Install

1. Install the formula:

   ```sh
   brew install tdmackey/public-inbox/public-inbox
   ```

2. Test the installation:

   ```sh
   brew test tdmackey/public-inbox/public-inbox
   ```

3. Show the `lei` help:

   ```sh
   lei --help
   ```

The tap does not publish bottles (prebuilt packages). Homebrew builds the
formula from source.

## Source and dependencies

The formula uses a fixed commit from the
[`tdmackey/public-inbox`](https://github.com/tdmackey/public-inbox) fork:
[`7b106f5fa70585820cfeb937a62ad7ac25ede312`](https://github.com/tdmackey/public-inbox/commit/7b106f5fa70585820cfeb937a62ad7ac25ede312).
This commit adds three portability changes to an upstream `master` commit.
A later commit adds the fork's GitHub CI workflow and a Darwin test adjustment.
The source archive excludes that later commit.

The formula fixes the source archive and each Perl/Xapian resource to a version
and SHA-256 checksum. Homebrew fetches these archives before the build.
The formula blocks network access during the build.

The packaged dependencies cover upstream's `lei` profile. Optional server
dependencies, such as Plack for `public-inbox-httpd`, are not included.

Upstream has both an `INSTALL` file and an `install/` directory. These names
conflict on the default macOS filesystem, which ignores letter case.
The source archive omits `install/`. This directory contains Linux package
manager helpers that the build and installed tools do not use.

Use [`scripts/package-source.sh`](scripts/package-source.sh) to reproduce the
archive from the fixed commit. See [Contributing](CONTRIBUTING.md) for the
command and checksum checks.

When an upstream release includes the portability changes, the formula can
use its release archive. Check for filename conflicts before changing the
archive source.

## Tests and platform coverage

The tap's [CI workflow](.github/workflows/tests.yml) builds the formula on
`macos-latest` with Apple Silicon and on Linux. It runs the source archive tests,
Homebrew checks, a source build, a library linkage check, and the formula test.

The formula test creates and indexes a version 2 inbox on both platforms.
On macOS, it also imports a message with `lei`, finds that message, and stops
the test daemon. Homebrew's Linux test sandbox blocks a directory operation
that the `lei` store worker requires. The source fork tests Linux `lei`
outside that sandbox.

The source fork tests the native `SOCK_SEQPACKET` transport on Linux.
It also forces the `SOCK_STREAM` fallback on Linux and tests automatic fallback
on macOS. These transports carry interprocess communication (IPC) records.
The [test matrix](design/macos-ipc-test-matrix.md) separates required evidence
from current CI coverage and exclusions.

Older macOS releases and Intel systems are compatibility targets. They do not
have continuous test coverage in this tap.

## Repository files

| File | Purpose |
| --- | --- |
| [`Formula/public-inbox.rb`](Formula/public-inbox.rb) | Install the fixed source commit, dependencies, `public-inbox-*` commands, and `lei`. |
| [`.github/workflows/tests.yml`](.github/workflows/tests.yml) | Build and test the formula on macOS and Linux. |
| [`scripts/package-source.sh`](scripts/package-source.sh) | Create and check a source archive without the conflicting `install/` directory. |
| [`tests/package-source.sh`](tests/package-source.sh) | Test archive creation and error handling with temporary Git repositories. |
| [`design/macos-ipc-record-rfc.md`](design/macos-ipc-record-rfc.md) | Describe the implemented IPC design and proposed upstream patch series. |
| [`design/macos-ipc-rfc.md`](design/macos-ipc-rfc.md) | Preserve the earlier design proposal for reference. |
| [`design/macos-ipc-test-matrix.md`](design/macos-ipc-test-matrix.md) | Define platform tests and required release evidence. |

## Upstream review

The source fork preserves public-inbox's Git history. The canonical repository
is [`public-inbox.org/public-inbox.git`](https://public-inbox.org/public-inbox.git).
The formula uses a fixed commit, so changes to a branch do not change its source.

public-inbox reviews patches by email. The
[record transport RFC](design/macos-ipc-record-rfc.md) describes the proposed
three-patch series and the test evidence to include. This repository does not
send upstream email automatically.

## License

The tap's formula, scripts, and documentation use the BSD-2-Clause license.
See [`LICENSE`](LICENSE). public-inbox is separate software and uses
AGPL-3.0-or-later.
