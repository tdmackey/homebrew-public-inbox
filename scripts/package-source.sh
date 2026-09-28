#!/bin/sh
# Build a source archive that works on case-insensitive file systems.
set -eu

if test "$#" -lt 3 || test "$#" -gt 4
then
  echo "usage: $0 PUBLIC_INBOX_REPO COMMIT VERSION [OUTPUT]" >&2
  exit 2
fi

source_repo=$1
version=$3
case "${version}" in
  ''|*/*|*\\*|*'
'*)
    echo "VERSION must be one nonempty path component without control characters" >&2
    exit 2
    ;;
esac
if printf '%s' "${version}" | LC_ALL=C grep -q '[[:cntrl:]]'
then
  echo "VERSION must be one nonempty path component without control characters" >&2
  exit 2
fi

output=${4:-"public-inbox-${version}.tar.gz"}
case "${output}" in
  /*) ;;
  *) output="${PWD}/${output}" ;;
esac

if test -d "${output}"
then
  echo "OUTPUT must be a file, not a directory: ${output}" >&2
  exit 2
fi

# Resolve the ref once. Pass only the resulting commit ID to git archive.
commit=$(git --no-replace-objects -C "${source_repo}" rev-parse --verify --end-of-options "${2}^{commit}")
attributes=$(git -C "${source_repo}" rev-parse --path-format=absolute --git-path info/attributes)
if test -s "${attributes}"
then
  echo "use a source repository without local info/attributes overrides: ${attributes}" >&2
  exit 1
fi
tmp_dir=$(mktemp -d "${output%/*}/.public-inbox.XXXXXX")
tmp_tar="${tmp_dir}/source.tar"
tmp_gz="${tmp_dir}/source.tar.gz"
trap 'rm -f "${tmp_tar}" "${tmp_gz}"; rmdir "${tmp_dir}"' 0
trap 'exit 1' 1 2 15

# Use committed attributes, omit local object replacements, set archive
# permissions, and omit the gzip timestamp and file name.
GIT_ATTR_NOSYSTEM=1 git --no-replace-objects \
  -c core.autocrlf=false -c core.attributesFile=/dev/null -c tar.umask=0002 \
  -C "${source_repo}" archive \
  --format=tar \
  --prefix="public-inbox-${version}/" \
  --output="${tmp_tar}" \
  "${commit}" -- . ':(exclude)install'
gzip -n -9 -c "${tmp_tar}" >"${tmp_gz}"

# Check the completed archive before replacing an existing output file.
listing=$(tar -tf "${tmp_gz}")
if ! printf '%s\n' "${listing}" | grep -Fqx "public-inbox-${version}/INSTALL"
then
  echo "archive does not contain the required INSTALL file" >&2
  exit 1
fi
if printf '%s\n' "${listing}" | grep -Fqx \
  -e "public-inbox-${version}/install" -e "public-inbox-${version}/install/"
then
  echo "archive unexpectedly contains the case-colliding install/ directory" >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1
then
  checksum=$(shasum -a 256 -b <"${tmp_gz}")
else
  checksum=$(sha256sum -b <"${tmp_gz}")
fi
mv -f "${tmp_gz}" "${output}"
printf '%s *%s\n' "${checksum%% *}" "${output}"
