# Contributing

Contributions should keep this tap reproducible, reviewable, and close to
upstream public-inbox.

## Formula changes

- Use the canonical immutable public-inbox release archive and a verified
  SHA-256.
- Do not fetch required code during `install`, `post_install`, or at runtime.
- Declare every Perl dependency as a checksummed `resource`, in topological
  build order.
- Keep the Xapian bindings resource at exactly the same version as Homebrew's
  `xapian` formula.
- Add a formula `revision` when a patch or packaged resource changes without an
  upstream public-inbox version change.
- Keep `lei` and public-inbox in one formula; they are one upstream
  distribution with an overlapping installed payload.

## macOS portability patch

Develop the fix in the `tdmackey/public-inbox` fork and submit the same clean
change upstream. The tap must reference a full immutable commit patch and its
verified checksum, never a moving branch. Once a formula references a fork
commit, do not rewrite or delete it.

The patch is acceptable for this tap only when it:

- preserves the existing `SOCK_SEQPACKET` path where the platform supports it;
- provides a tested macOS fallback without assuming record boundaries that the
  fallback transport does not provide;
- passes upstream tests plus offline `lei import` and `lei q` tests on macOS
  and Linux.

Keep the patch until a stable upstream release contains the fix. At that point,
bump the source release, remove the patch, and rebuild from source before
publishing new bottles.

## Local checks

With the tap checked out in Homebrew's tap directory, run:

```sh
brew style tdmackey/public-inbox/public-inbox
brew audit --new --formula tdmackey/public-inbox/public-inbox
brew audit --strict --online tdmackey/public-inbox/public-inbox
HOMEBREW_NO_INSTALL_FROM_API=1 \
  brew install --build-from-source tdmackey/public-inbox/public-inbox
brew test tdmackey/public-inbox/public-inbox
brew linkage --test public-inbox
```

Do not remove the scaffold guard or enable formula build CI until the patch and
complete Perl dependency closure are present. Pull requests should explain the
source of every new version and checksum and describe the macOS and Linux test
coverage used.
