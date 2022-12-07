#!/bin/bash -eu
#
# Compares Android-TARGET.mk files generated by the mixed build
# against the same file generated by the reference build.
# This is the wrapper around build/bazel/mkcompare tool
# Usage:
#  mkmodules_diff [--bazel-mode-staging] <mkcompare_option> ...
# Android-TARGET.mk files that are compared are for the product
# defined by the TARGET_PRODUCT and TARGET_BUILD_VARIANT environment
# variables.
# Without --bazel-mode-staging option, the mixed build is run with
# --bazel-mode-dev option.
# The output can be safely redirected to a file, it does not include
# the noise from the build.

declare -r builder=build/soong/soong_ui.bash
[[ -x ${builder} ]] || \
  { echo "current directory should be the root of the Android source tree"; exit 1; }
export ANDROID_QUIET_BUILD=yes
declare -a mkargs
declare bazel_mode=--bazel-mode-dev
for a in $@; do
  if [[ "$a" =~ ^--bazel-mode ]]; then
    bazel_mode="$a"
  else
    mkargs+=("$a")
  fi
done
${builder} --make-mode nothing >/dev/null
declare -r mkmod_file=$(realpath "out/soong/Android-${TARGET_PRODUCT}.mk")
mv ${mkmod_file} ${mkmod_file}.ref
${builder} --make-mode "${bazel_mode}"  nothing >/dev/null
cd build/bazel/mkcompare
go run cmd/mkcompare.go ${mkargs[@]} ${mkmod_file}.ref ${mkmod_file}
