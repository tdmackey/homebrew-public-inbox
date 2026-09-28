# Contributing

Keep builds reproducible and changes small enough to review.
Keep the tap close to upstream public-inbox.

## Documentation style

Use a style based on
[ASD-STE100 Simplified Technical English](https://www.asd-ste100.org/STE_faq.html).
This repository does not claim full compliance with the standard's dictionary.

- Write short sentences with one main idea.
- Use the active voice and name the component that performs an action.
- Give one instruction per step. Put the condition before the instruction.
- Use the same term for the same object or action.
- Define an abbreviation when a reader first needs it.
- Keep command names, API names, error codes, and protocol bytes exact.
- Separate current behavior, proposed behavior, and recorded test results.

Preserve the technical meaning when you simplify a sentence.
Keep the license text unchanged.

## Formula changes

- Use a fixed source archive and verify its SHA-256 checksum.
- Use a canonical upstream release when it includes the required fixes.
- Until then, use the fork snapshot described below.
- Do not download required code during `install`, `post_install`, or runtime.
- Declare each required Perl dependency as a resource with a checksum.
- Put each resource after the resources that it needs to build.
- Match `xapian-bindings` to the installed Homebrew `xapian` version.
- Increase the formula `revision` when the installed package changes without
  a source version change.
- Keep `lei` and public-inbox in one formula. Upstream distributes them together.

Explain the source of each new version and checksum in the pull request.
Include the commands and results used to test the change.

## Source archive

The formula uses a fork commit that includes the portability fixes.
It does not apply a separate patch during installation.
Do not rewrite or delete a commit that the formula uses.

The upstream `INSTALL` file conflicts with the `install/` directory on a
filesystem that ignores letter case. The packaging script omits `install/`
from the archive. It reads Git objects and does not change the source checkout.

To reproduce the current archive:

1. Clone the source fork without a checkout, or use an existing clone:

   ```sh
   git clone --no-checkout https://github.com/tdmackey/public-inbox.git public-inbox-source
   ```

2. From this tap's directory, run:

   ```sh
   sh scripts/package-source.sh public-inbox-source \
     7b106f5fa70585820cfeb937a62ad7ac25ede312 \
     2.1.0-62-g7b106f5f
   ```

3. Compare the printed SHA-256 with the source checksum in
   [`Formula/public-inbox.rb`](Formula/public-inbox.rb).

The optional fourth argument sets the output path. Its parent directory must
exist. The script checks the archive before it replaces the output file.
The version must not contain a slash, backslash, or control character.
Use a source clone without local `info/attributes` overrides.
The script uses committed attributes and ignores user attributes and Git
replacement objects.

For a source update, select the full product commit ID and a matching version.
Exclude commits that contain only the fork's CI setup.
Generate the archive and verify its contents and checksum before publication.
Then update the formula's URL, version, and checksum together.

## Portability changes

Develop public-inbox changes in the `tdmackey/public-inbox` fork.
Prepare the same product changes for upstream review.

The transport changes must:

- preserve the existing `SOCK_SEQPACKET` path where it works;
- provide a tested macOS fallback that preserves complete IPC records;
- pass the applicable upstream tests;
- pass local `lei import` and `lei q` tests on macOS and Linux.

See the [record transport RFC](design/macos-ipc-record-rfc.md) for the
implemented design. Use the [test matrix](design/macos-ipc-test-matrix.md) to
record platform coverage, exclusions, and missing evidence.

When an upstream release contains the fixes, update the formula to that release.
Check that its archive can be extracted on the default macOS filesystem.
Build and test from source before publishing bottles.

## Local checks

Run the source archive tests from this repository:

```sh
sh tests/package-source.sh
```

These tests require a POSIX shell, Git, tar, gzip, and a SHA-256 command
(`shasum` or `sha256sum`). They do not require Homebrew or network access.

For formula checks, put this checkout in Homebrew's tap directory.
Run these commands on macOS or Linux:

```sh
brew style tdmackey/public-inbox/public-inbox
brew audit --strict --online tdmackey/public-inbox/public-inbox
HOMEBREW_NO_INSTALL_FROM_API=1 \
  brew install --build-from-source tdmackey/public-inbox/public-inbox
brew test tdmackey/public-inbox/public-inbox
brew linkage --test --strict tdmackey/public-inbox/public-inbox
```

If the formula is already installed, use `brew reinstall --build-from-source`
with the same formula name and environment setting.
For a new formula, also run `brew audit --new --formula` with its name.

CI must run the source build, linkage check, and formula test on both platforms.
`brew test-bot` can skip a formula when a dependency has no suitable bottle.
The workflow therefore runs these checks directly as well.
