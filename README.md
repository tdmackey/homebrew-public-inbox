# Homebrew public-inbox

A Homebrew tap for [public-inbox](https://public-inbox.org/) and its `lei`
command-line interface on macOS, with Linux kept as a regression platform.

## Status

This repository is in active bring-up and is not yet a working installer. The
formula is deliberately disabled until public-inbox's `SOCK_SEQPACKET` IPC
path has an upstreamable, immutable, CI-tested macOS fallback patch.

The canonical v2.1.0 archive and its SHA-256 are already verified in the
formula. The complete `lei` Perl dependency closure, secure IMAP/TLS modules,
and matching Xapian 2.1.0 Perl bindings are pinned to hash-verified archives
and installed without network access. No bottles are published while the
formula remains incomplete.

## Planned installation

Once the status above is cleared, users will install the formula directly:

```sh
brew install tdmackey/public-inbox/public-inbox
```

During the source-only validation phase, use:

```sh
HOMEBREW_NO_INSTALL_FROM_API=1 \
  brew install --build-from-source tdmackey/public-inbox/public-inbox
brew test tdmackey/public-inbox/public-inbox
```

## Repository layout

- `Formula/public-inbox.rb` packages the canonical upstream release and both
  the `public-inbox-*` and `lei` commands.
- `.github/workflows/tests.yml` runs Homebrew syntax checks on macOS and Linux.
  Full source builds are gated until the formula is ready.
- `design/macos-ipc-rfc.md` documents the compatibility contract and transport
  design intended for upstream review.
- `design/macos-ipc-test-matrix.md` defines the macOS/Linux release gates.

The macOS source change belongs in the `tdmackey/public-inbox` portability fork,
not in this tap. The formula should consume an immutable, checksummed commit
patch. When upstream releases the fix, update the canonical source and remove
the patch.

## Enabling build CI

After the formula's `TODO(PORTABILITY)` item is complete:

1. run the functional `lei import`/`lei q` test locally on macOS and Linux;
2. remove `disable!` and the `FORMULA_SCAFFOLD_INCOMPLETE` marker from the
   formula;
3. set the GitHub Actions repository variable `FORMULA_READY` to `true`;
4. open a pull request and require every Homebrew CI job to pass.

Add bottle publication only after source builds pass on every macOS
architecture and release that the tap intends to support. Native Perl and
Xapian code means those bottle checks cannot be inferred from a single runner.

## Licensing

The tap's own formula and documentation are BSD-2-Clause licensed; see
`LICENSE`. public-inbox is separate upstream software licensed
AGPL-3.0-or-later.
