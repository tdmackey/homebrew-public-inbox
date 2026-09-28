#!/bin/sh
# Test source packaging with a small Git repository. No network is required.
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
package_script="${project_dir}/scripts/package-source.sh"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/public-inbox-package-test.XXXXXX")
trap 'rm -rf "${test_dir}"' 0
trap 'exit 1' 1 2 15

fail()
{
  echo "FAIL: $*" >&2
  exit 1
}

# Keep fixture commits independent of the user's Git configuration.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME='Packaging Test'
export GIT_AUTHOR_EMAIL='test@example.invalid'
export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}"
export GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"
export GIT_AUTHOR_DATE='2000-01-01T00:00:00Z'
export GIT_COMMITTER_DATE="${GIT_AUTHOR_DATE}"

repo="${test_dir}/source repo"
mkdir "${repo}"
git -C "${repo}" init -q
git -C "${repo}" config core.excludesFile /dev/null
blob=$(printf 'fixture\n' | git -C "${repo}" hash-object -w --stdin)
# Write the index directly so INSTALL and install/ can coexist on macOS and
# Windows file systems that treat upper- and lowercase names as equal.
for name in INSTALL README install/README excluded
do
  git -c core.ignorecase=false -C "${repo}" update-index --add --cacheinfo "100644,${blob},${name}"
done
git -C "${repo}" update-index --add --cacheinfo "100755,${blob},script"
attributes_blob=$(printf 'excluded export-ignore\n' | git -C "${repo}" hash-object -w --stdin)
git -C "${repo}" update-index --add --cacheinfo "100644,${attributes_blob},.gitattributes"
tree=$(git -C "${repo}" write-tree)
commit=$(printf 'fixture\n' | git -C "${repo}" commit-tree "${tree}")
git -C "${repo}" update-ref refs/heads/source "${commit}"

output="${test_dir}/source archive.tar.gz"
sh "${package_script}" "${repo}" source 1.0 "${output}" >"${test_dir}/checksum"
listing=$(tar -tf "${output}")
printf '%s\n' "${listing}" | grep -Fqx 'public-inbox-1.0/INSTALL' || fail 'INSTALL is missing'
printf '%s\n' "${listing}" | grep -Fqx 'public-inbox-1.0/script' || fail 'source file is missing'
if printf '%s\n' "${listing}" | grep -Fq 'public-inbox-1.0/install'
then
  fail 'install/ was not excluded'
fi
if printf '%s\n' "${listing}" | grep -Fqx 'public-inbox-1.0/excluded'
then
  fail 'committed export-ignore was not applied'
fi
if command -v shasum >/dev/null 2>&1
then
  shasum -a 256 -b "${output}" >"${test_dir}/expected-checksum"
else
  sha256sum -b "${output}" >"${test_dir}/expected-checksum"
fi
cmp "${test_dir}/checksum" "${test_dir}/expected-checksum" || fail 'checksum output is incorrect'

# User settings and worktree attributes must not change the published bytes.
git -C "${repo}" config tar.umask 0077
printf 'README export-ignore\n' >"${test_dir}/user-attributes"
git -C "${repo}" config core.attributesFile "${test_dir}/user-attributes"
printf 'INSTALL export-ignore\n' >"${repo}/.gitattributes"
(umask 077; sh "${package_script}" "${repo}" "${commit}" 1.0 "${test_dir}/repeat.tar.gz") >/dev/null
cmp "${output}" "${test_dir}/repeat.tar.gz" || fail 'archive is not reproducible'

# Version labels are literal strings, including regular-expression characters.
sh "${package_script}" "${repo}" "${commit}" '1.0[rc1]' "${test_dir}/literal.tar.gz" >/dev/null
tar -tf "${test_dir}/literal.tar.gz" | grep -Fqx 'public-inbox-1.0[rc1]/INSTALL' || fail 'version was not literal'

cp "${output}" "${test_dir}/original.tar.gz"
expect_failure()
{
  if sh "${package_script}" "$@" >"${test_dir}/stdout" 2>"${test_dir}/stderr"
  then
    fail "unexpected success: $*"
  fi
  cmp "${output}" "${test_dir}/original.tar.gz" || fail 'failure replaced the output'
  for temporary in "${test_dir}"/.public-inbox.*
  do
    test ! -d "${temporary}" || fail 'temporary directory was not removed'
  done
}

# An archive without INSTALL must fail without replacing a previous release.
git -C "${repo}" update-index --force-remove INSTALL
tree=$(git -C "${repo}" write-tree)
missing_install=$(printf 'missing INSTALL\n' | git -C "${repo}" commit-tree "${tree}")
expect_failure "${repo}" "${missing_install}" 1.0 "${output}"
# Git replace refs must not change the contents of a pinned source commit.
git -C "${repo}" replace "${commit}" "${missing_install}"
sh "${package_script}" "${repo}" "${commit}" 1.0 "${test_dir}/unreplaced.tar.gz" >/dev/null
cmp "${output}" "${test_dir}/unreplaced.tar.gz" || fail 'local replacement changed the archive'
printf 'README export-ignore\n' >"${repo}/.git/info/attributes"
expect_failure "${repo}" "${commit}" 1.0 "${output}"
rm "${repo}/.git/info/attributes"
expect_failure "${repo}" does-not-exist 1.0 "${output}"
expect_failure "${repo}" --all 1.0 "${output}"
expect_failure "${repo}" "${blob}" 1.0 "${output}"
expect_failure "${repo}" "${commit}" '' "${output}"
expect_failure "${repo}" "${commit}" '../bad' "${output}"
expect_failure "${repo}" "${commit}" 'bad\path' "${output}"
expect_failure "${repo}" "${commit}" 'bad
version' "${output}"
expect_failure "${repo}" "${commit}" "$(printf 'bad\rversion')" "${output}"
expect_failure "${repo}" "${commit}" 1.0 "${test_dir}/missing/output.tar.gz"
expect_failure "${repo}" "${commit}" 1.0 "${test_dir}"
test ! -f "${test_dir}/source.tar.gz" || fail 'archive was moved into an output directory'

# A compression failure must also preserve the existing release.
mkdir "${test_dir}/bin"
printf '#!/bin/sh\nexit 1\n' >"${test_dir}/bin/gzip"
chmod +x "${test_dir}/bin/gzip"
PATH="${test_dir}/bin:${PATH}" expect_failure "${repo}" "${commit}" 1.0 "${output}"
rm "${test_dir}/bin/gzip"

# Publish only after the checksum tool has also succeeded.
printf '#!/bin/sh\nexit 1\n' >"${test_dir}/bin/shasum"
chmod +x "${test_dir}/bin/shasum"
PATH="${test_dir}/bin:${PATH}" expect_failure "${repo}" "${commit}" 1.0 "${output}"

echo 'Source packaging tests passed.'
