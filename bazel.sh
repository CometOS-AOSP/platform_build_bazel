#!/bin/bash
set -eo pipefail

# TODO: Refactor build/make/envsetup.sh to make gettop() available elsewhere
function gettop
{
    local TOPFILE=build/bazel/bazel.sh
    if [ -n "$TOP" -a -f "$TOP/$TOPFILE" ] ; then
        # The following circumlocution ensures we remove symlinks from TOP.
        (cd "$TOP"; PWD= /bin/pwd)
    else
        if [ -f $TOPFILE ] ; then
            # The following circumlocution (repeated below as well) ensures
            # that we record the true directory name and not one that is
            # faked up with symlink names.
            PWD= /bin/pwd
        else
            local HERE=$PWD
            local T=
            while [ \( ! \( -f $TOPFILE \) \) -a \( "$PWD" != "/" \) ]; do
                \cd ..
                T=`PWD= /bin/pwd -P`
            done
            \cd "$HERE"
            if [ -f "$T/$TOPFILE" ]; then
                echo "$T"
            fi
        fi
    fi
}

# TODO: Refactor build/soong/scripts/microfactory.bash to make getoutdir() available elsewhere
function getoutdir
{
    local out_dir="${OUT_DIR-}"
    if [ -z "${out_dir}" ]; then
        if [ "${OUT_DIR_COMMON_BASE-}" ]; then
            out_dir="${OUT_DIR_COMMON_BASE}/$(basename ${TOP})"
        else
            out_dir="out"
        fi
    fi
    if [[ "${out_dir}" != /* ]]; then
        out_dir="${TOP}/${out_dir}"
    fi
    echo "${out_dir}"
}

TOP="$(gettop)"
if [ ! "$TOP" ]; then
    >&2 echo "Couldn't locate the top of the tree.  Try setting TOP."
    exit 1
fi

ABSOLUTE_OUT_DIR="$(getoutdir)"
# Store all bazel-related metadata files in this subdir of OUT_DIR.
BAZEL_METADATA_OUT="${ABSOLUTE_OUT_DIR}/bazel"
mkdir -p "${BAZEL_METADATA_OUT}"

case $(uname -s) in
    Darwin)
        ANDROID_BAZEL_PATH="${TOP}/prebuilts/bazel/darwin-x86_64/bazel"
        ANDROID_BAZELRC_NAME="darwin.bazelrc"
        ANDROID_BAZEL_JDK_PATH="${TOP}/prebuilts/jdk/jdk11/darwin-x86"

        # Lock down PATH in action execution environment, thereby removing
        # Bazel's default /bin, /usr/bin, /usr/local/bin and ensuring
        # hermeticity from the system.
        #
        # The new PATH components are:
        #
        # - prebuilts/build-tools/path: contains checked-in tools that can be
        #   used as executables in actions.
        #
        # - out/.path: a special directory created by path_interposer with
        #   config from ui/build/paths/config.go for allowlisting specific
        #   binaries not in prebuilts/build-tools/path, but on the host system.
        #   If one runs Bazel without soong_ui, then this  directory wouldn't
        #   exist, making standalone Bazel execution's PATH variable stricter than
        #   Bazel execution within soong_ui.
        RESTRICTED_PATH="${TOP}/prebuilts/build-tools/path/darwin-x86:${ABSOLUTE_OUT_DIR}/.path"
        ;;
    Linux)
        ANDROID_BAZEL_PATH="${TOP}/prebuilts/bazel/linux-x86_64/bazel"
        ANDROID_BAZELRC_NAME="linux.bazelrc"
        ANDROID_BAZEL_JDK_PATH="${TOP}/prebuilts/jdk/jdk11/linux-x86"
        RESTRICTED_PATH="${TOP}/prebuilts/build-tools/path/linux-x86:${ABSOLUTE_OUT_DIR}/.path"
        ;;
    *)
        >&2 echo "Bazel is supported on Linux and Darwin only. Your OS is not supported for Bazel usage, based on 'uname -s': $(uname -s)"
        exit 1
        ;;
esac

function verify_soong_outputs_exist() {
    local to_check="${ABSOLUTE_OUT_DIR}/.path"
    local no_soong=0
    if [[ ! -d "${to_check}" ]]; then
      no_soong=1
    fi

    local bazel_configs=(
        "bp2build"
        "api_bp2build"
        "queryview"
    )
    local valid_bazel_config=0
    for c in "${bazel_configs[@]}"
    do
        if [[ -d "${ABSOLUTE_OUT_DIR}/soong/""${c}" ]]; then
          valid_bazel_config=1
        fi
    done

    if [[ "${no_soong}" -eq "1" || "${valid_bazel_config}" -eq "0" ]]; then
        >&2 echo "Error: missing generated Bazel files. Have you run bp2build or queryview?"
        >&2 echo "Run bp2build with the command: m bp2build"
        >&2 echo "Run queryview with the command: m queryview"
        >&2 echo "Alternatively, for non-queryview applications, invoke Bazel using 'b' with the command: source envsetup.sh; b query/build/test <targets>"
        exit 1
    fi
}

function create_bazelrc() {
    cat > "${BAZEL_METADATA_OUT}/generated.bazelrc" <<EOF
# This file is generated by tools/bazel. Do not edit manually.
build --action_env=PATH=${RESTRICTED_PATH}

# Run bazel query from the workspace, without cd'ing into \$OUT_DIR/soong/queryview
common:queryview --package_path=${ABSOLUTE_OUT_DIR}/soong/queryview

# Run bazel build from the workspace, without cd'ing into \$OUT_DIR/soong/api_bp2build
common:api_bp2build --package_path=${ABSOLUTE_OUT_DIR}/soong/api_bp2build

# Run bazel build from the workspace, without cd'ing into \$OUT_DIR/soong/workspace
common:bp2build --package_path=${ABSOLUTE_OUT_DIR}/soong/workspace
EOF
}

# Return 1 if STANDALONE_BAZEL is truthy
function is_standalone_bazel() {
    [[ ${STANDALONE_BAZEL} =~ ^(true|TRUE|1)$ ]]
}

case "x${ANDROID_BAZELRC_PATH}" in
    x)
      # Path not provided, use default.
      if is_standalone_bazel; then
        # Standalone bazel uses the empty /dev/null bazelrc
        # This is necessary since some configs in common.bazelrc depend on soong_injection
        ANDROID_BAZELRC_PATH=/dev/null
      else
        ANDROID_BAZELRC_PATH="${TOP}/build/bazel"
      fi
        ;;
    x/*)
        # Absolute path, take it as-is.
        ANDROID_BAZELRC_PATH="${ANDROID_BAZELRC_PATH}"
        ;;
    x*)
        # Relative path, consider it relative to TOP.
        ANDROID_BAZELRC_PATH="${TOP}/${ANDROID_BAZELRC_PATH}"
        ;;
esac

if [ -d "${ANDROID_BAZELRC_PATH}" ]; then
    # If we're given a directory, find the correct bazelrc file there.
    ANDROID_BAZELRC_PATH="${ANDROID_BAZELRC_PATH}/${ANDROID_BAZELRC_NAME}"
fi


if [ -n "$ANDROID_BAZEL_PATH" -a -f "$ANDROID_BAZEL_PATH" ]; then
    export ANDROID_BAZEL_PATH
else
    >&2 echo "Couldn't locate Bazel binary"
    exit 1
fi

if [ "$ANDROID_BAZELRC_PATH" == "/dev/null" ] || [ -n "$ANDROID_BAZELRC_PATH" -a -f "$ANDROID_BAZELRC_PATH" ]; then
    export ANDROID_BAZELRC_PATH
else
    >&2 echo "Couldn't locate bazelrc file for Bazel"
    exit 1
fi

if [ -n "$ANDROID_BAZEL_JDK_PATH" -a -d "$ANDROID_BAZEL_JDK_PATH" ]; then
    export ANDROID_BAZEL_JDK_PATH
else
    >&2 echo "Couldn't locate JDK to use for Bazel"
    exit 1
fi

# In order to be able to load JNI libraries, this directory needs to exist
mkdir -p "${BAZEL_METADATA_OUT}/javatmp"

# Output a deps file. Soong will read these as dependencies for mixed builds
MIXED_BUILDS_DOTD="${BAZEL_METADATA_OUT}/bazel.list"
touch "${MIXED_BUILDS_DOTD}"
echo $ANDROID_BAZEL_PATH > "${MIXED_BUILDS_DOTD}"
echo $ANDROID_BAZELRC_PATH >> "${MIXED_BUILDS_DOTD}"
echo $ANDROID_BAZEL_JDK_PATH >> "${MIXED_BUILDS_DOTD}"


ADDITIONAL_FLAGS=()
if  is_standalone_bazel; then
    # STANDALONE_BAZEL is set.
    >&2 echo "WARNING: Using Bazel in standalone mode. This mode is not integrated with Soong and Make, and is not supported"
    >&2 echo "for Android Platform builds. Use this mode at your own risk."
    >&2 echo
else
    # STANDALONE_BAZEL is not set.
    >&2 echo "WARNING: Bazel support for the Android Platform is experimental and is undergoing development."
    >&2 echo "WARNING: Currently, build stability is not guaranteed. Thank you."
    >&2 echo

    # Generate a bazelrc with dynamic content, like the absolute path to PATH variable values.
    create_bazelrc
    # Check that the Bazel synthetic workspace and other required inputs exist before handing over control to Bazel.
    verify_soong_outputs_exist
    ADDITIONAL_FLAGS+=("--bazelrc=${BAZEL_METADATA_OUT}/generated.bazelrc")
fi

# TODO(b/240354506): Re-enable hsperfdata file creation without causing SIGBUS errors
JAVA_HOME="${ANDROID_BAZEL_JDK_PATH}" "${ANDROID_BAZEL_PATH}" \
  --server_javabase="${ANDROID_BAZEL_JDK_PATH}" \
  --output_user_root="${BAZEL_METADATA_OUT}/output_user_root" \
  --host_jvm_args=-Djava.io.tmpdir="${BAZEL_METADATA_OUT}/javatmp" \
  --nohome_rc --nosystem_rc \
  --bazelrc="${ANDROID_BAZELRC_PATH}" \
  "${ADDITIONAL_FLAGS[@]}" \
  "$@"
