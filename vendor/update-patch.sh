#!/bin/sh

version=fe7077c7e5e55721e77e7dbc2af2c044851cef20

set -e -o pipefail

TMP="$(mktemp -d)"
trap "rm -rf $TMP" EXIT

pkg=patch

rm -rf $pkg
mkdir -p $pkg/src

(
	cd $TMP
	git clone https://github.com/hannesm/$pkg.git
	cd $pkg
	git checkout $version
)

src=$TMP/$pkg

(
	cp -v $src/src/*.{ml,mli} $pkg/
	rm $pkg/patch_command.ml
) || true

git checkout $pkg/dune

git add -A .

