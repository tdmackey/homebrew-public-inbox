#!/bin/sh
# Build the case-safe source archive consumed by Formula/public-inbox.rb.
set -eu

if test "$#" -lt 3 || test "$#" -gt 4
then
  echo "usage: $0 PUBLIC_INBOX_REPO COMMIT VERSION [OUTPUT]" >&2
  exit 2
fi

source_repo=$1
commit=$2
version=$3
output=${4:-"public-inbox-${version}.tar.gz"}
case "${output}" in
  /*) ;;
  *) output="${PWD}/${output}" ;;
esac

git -C "${source_repo}" cat-file -e "${commit}^{commit}"
tmp_tar="${output}.tar.$$"
tmp_gz="${output}.gz.$$"
trap 'rm -f "${tmp_tar}" "${tmp_gz}"' 0 1 2 15

# Disable checkout line-ending conversion and normalize the gzip header.  This
# keeps the release byte-for-byte reproducible across maintainer machines.
git -c core.autocrlf=false -C "${source_repo}" archive \
  --format=tar \
  --prefix="public-inbox-${version}/" \
  --output="${tmp_tar}" \
  "${commit}" -- . ':(exclude)install'
gzip -n -9 -c "${tmp_tar}" >"${tmp_gz}"
mv "${tmp_gz}" "${output}"
rm -f "${tmp_tar}"
trap - 0 1 2 15

listing=$(tar -tf "${output}")
printf '%s\n' "${listing}" | grep -qx "public-inbox-${version}/INSTALL"
if printf '%s\n' "${listing}" | grep -q "^public-inbox-${version}/install/"
then
  echo "archive unexpectedly contains the case-colliding install/ directory" >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1
then
  shasum -a 256 "${output}"
else
  sha256sum "${output}"
fi
