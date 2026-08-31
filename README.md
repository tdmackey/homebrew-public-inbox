# Homebrew public-inbox

A Homebrew tap for [public-inbox](https://public-inbox.org/) and its `lei`
command-line interface on macOS, with Linux kept as a regression platform.

## Status

The formula installs public-inbox and `lei` from an immutable commit in the
[`tdmackey/public-inbox`](https://github.com/tdmackey/public-inbox) portability
fork. That commit is upstream `master` plus three focused compatibility
commits; GitHub-only CI is kept in a fourth commit so the source series can be
submitted upstream without tap-specific changes.

All source and Perl/Xapian resources are pinned to hash-verified archives. The
build is network-isolated after Homebrew fetches those resources. Bottles are
not published yet, so installation builds from source.

Upstream contains both a top-level `INSTALL` file and an `install/` directory,
which cannot coexist on the default case-insensitive macOS filesystem. The
formula therefore uses a reproducible `git archive` snapshot of the exact
product commit that omits only `install/`, a set of Linux package-manager
helpers not used by the build or installed tools. Run
`scripts/package-source.sh` to reproduce and checksum that release asset.

## Installation

Install directly from the tap:

```sh
brew install tdmackey/public-inbox/public-inbox
```

Then verify the installed formula and try `lei`:

```sh
brew test tdmackey/public-inbox/public-inbox
lei --help
```

## Repository layout

- `Formula/public-inbox.rb` packages the immutable portability commit and both
  the `public-inbox-*` and `lei` commands.
- `.github/workflows/tests.yml` builds and tests the formula on macOS and Linux.
- `scripts/package-source.sh` produces the case-safe source release asset from
  an exact commit without modifying the source tree.
- `design/macos-ipc-record-rfc.md` documents the implemented compatibility
  contract and transport design intended for upstream review.
- `design/macos-ipc-rfc.md` retains the superseded single-owner topology
  proposal and its alternatives analysis as design history.
- `design/macos-ipc-test-matrix.md` defines the macOS/Linux release gates.

The source fork retains the canonical public-inbox history and an `upstream`
remote pointing to `https://public-inbox.org/public-inbox.git`. The formula is
pinned to product commit
[`7b106f5f`](https://github.com/tdmackey/public-inbox/commit/7b106f5fa70585820cfeb937a62ad7ac25ede312),
not a moving branch. When upstream merges and releases the portable IPC work,
the formula can return to the canonical release archive without changing its
packaging model.

## Validation and upstreaming

The release gate covers Linux's native `SOCK_SEQPACKET` path, a forced
`SOCK_STREAM` fallback on Linux, and native fallback on Intel and Apple Silicon
macOS 15 and 26. The formula test initializes a v2 inbox, imports a message with
`lei`, queries it back, and shuts down the per-user daemon.

The three source commits are deliberately small enough for public-inbox's
email-based review flow. See the record-transport RFC for the proposed
`git format-patch` series, test evidence to include, and questions for upstream
maintainers. No upstream email is sent automatically from this repository.

## Licensing

The tap's own formula and documentation are BSD-2-Clause licensed; see
`LICENSE`. public-inbox is separate upstream software licensed
AGPL-3.0-or-later.
