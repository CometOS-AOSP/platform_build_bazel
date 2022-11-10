"""
Copyright (C) 2021 The Android Open Source Project

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

load(
    ":cc_library_common.bzl",
    "create_ccinfo_for_includes",
    "get_non_header_srcs",
    "is_external_directory",
    "parse_sdk_version",
    "system_dynamic_deps_defaults",
)
load(":stl.bzl", "stl_info_from_attr")
load(":clang_tidy.bzl", "ClangTidyInfo", "generate_clang_tidy_actions")
load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("//build/bazel/product_variables:constants.bzl", "constants")

CcStaticLibraryInfo = provider(fields = ["root_static_archive", "objects"])

def cc_library_static(
        name,
        deps = [],
        implementation_deps = [],
        dynamic_deps = [],
        implementation_dynamic_deps = [],
        whole_archive_deps = [],
        implementation_whole_archive_deps = [],
        system_dynamic_deps = None,
        runtime_deps = [],
        export_absolute_includes = [],
        export_includes = [],
        export_system_includes = [],
        local_includes = [],
        absolute_includes = [],
        hdrs = [],
        native_bridge_supported = False,  # TODO: not supported yet.
        use_libcrt = True,
        rtti = False,
        stl = "",
        cpp_std = "",
        c_std = "",
        # Flags for C and C++
        copts = [],
        # C++ attributes
        srcs = [],
        cppflags = [],
        # C attributes
        srcs_c = [],
        conlyflags = [],
        # asm attributes
        srcs_as = [],
        asflags = [],
        features = [],
        linkopts = [],
        alwayslink = None,
        target_compatible_with = [],
        # TODO(b/202299295): Handle data attribute.
        data = [],
        sdk_version = "",
        min_sdk_version = "",
        tags = [],
        tidy = None,
        tidy_checks = None,
        tidy_checks_as_errors = None,
        tidy_flags = None,
        tidy_disabled_srcs = None):
    "Bazel macro to correspond with the cc_library_static Soong module."

    exports_name = "%s_exports" % name
    locals_name = "%s_locals" % name
    cpp_name = "%s_cpp" % name
    c_name = "%s_c" % name
    asm_name = "%s_asm" % name

    toolchain_features = []
    toolchain_features += features

    if is_external_directory(native.package_name()):
        toolchain_features += [
            "-non_external_compiler_flags",
            "external_compiler_flags",
        ]
    else:
        toolchain_features += [
            "non_external_compiler_flags",
            "-external_compiler_flags",
        ]

    if rtti:
        toolchain_features += ["rtti"]
    if not use_libcrt:
        toolchain_features += ["use_libcrt"]
    if cpp_std:
        toolchain_features += [cpp_std, "-cpp_std_default"]
    if c_std:
        toolchain_features += [c_std, "-c_std_default"]

    if min_sdk_version:
        toolchain_features += parse_sdk_version(min_sdk_version) + ["-sdk_version_default"]

    if system_dynamic_deps == None:
        system_dynamic_deps = system_dynamic_deps_defaults

    _cc_includes(
        name = exports_name,
        includes = export_includes,
        absolute_includes = export_absolute_includes,
        system_includes = export_system_includes,
        # whole archive deps always re-export their includes, etc
        deps = deps + whole_archive_deps + dynamic_deps,
        target_compatible_with = target_compatible_with,
        tags = ["manual"],
    )

    stl_info = stl_info_from_attr(stl, False)
    linkopts = linkopts + stl_info.linkopts
    copts = copts + stl_info.cppflags

    _cc_includes(
        name = locals_name,
        includes = local_includes,
        absolute_includes = absolute_includes,
        deps = (
            implementation_deps +
            implementation_dynamic_deps +
            system_dynamic_deps +
            stl_info.static_deps +
            stl_info.shared_deps +
            implementation_whole_archive_deps
        ),
        target_compatible_with = target_compatible_with,
        tags = ["manual"],
    )

    # Silently drop these attributes for now:
    # - native_bridge_supported
    common_attrs = dict(
        [
            # TODO(b/199917423): This may be superfluous. Investigate and possibly remove.
            ("linkstatic", True),
            ("hdrs", hdrs),
            # Add dynamic_deps to implementation_deps, as the include paths from the
            # dynamic_deps are also needed.
            ("implementation_deps", [locals_name]),
            ("deps", [exports_name]),
            ("features", toolchain_features),
            ("toolchains", ["//build/bazel/platforms:android_target_product_vars"]),
            ("alwayslink", alwayslink),
            ("target_compatible_with", target_compatible_with),
            ("linkopts", linkopts),
        ],
    )

    # TODO(b/231574899): restructure this to handle other images
    copts += select({
        "//build/bazel/rules/apex:non_apex": [],
        "//conditions:default": [
            "-D__ANDROID_APEX__",
            # TODO(b/231322772): sdk_version/min_sdk_version if not finalized
            "-D__ANDROID_APEX_MIN_SDK_VERSION__=10000",
        ],
    })

    native.cc_library(
        name = cpp_name,
        srcs = srcs,
        copts = copts + cppflags,
        tags = ["manual"],
        **common_attrs
    )
    native.cc_library(
        name = c_name,
        srcs = srcs_c,
        copts = copts + conlyflags,
        tags = ["manual"],
        **common_attrs
    )
    native.cc_library(
        name = asm_name,
        srcs = srcs_as,
        copts = asflags,
        tags = ["manual"],
        **common_attrs
    )

    # Root target to handle combining of the providers of the language-specific targets.
    _cc_library_combiner(
        name = name,
        roots = [cpp_name, c_name, asm_name],
        deps = whole_archive_deps + implementation_whole_archive_deps,
        runtime_deps = runtime_deps,
        target_compatible_with = target_compatible_with,
        alwayslink = alwayslink,
        tags = tags,
        features = toolchain_features,
        tidy = tidy,
        srcs_cpp = srcs,
        srcs_c = srcs_c,
        copts_cpp = copts + cppflags,
        copts_c = copts + conlyflags,
        hdrs = hdrs,
        includes = [locals_name, exports_name],
        tidy_flags = tidy_flags,
        tidy_checks = tidy_checks,
        tidy_checks_as_errors = tidy_checks_as_errors,
        tidy_disabled_srcs = tidy_disabled_srcs,
    )

# Returns a CcInfo object which combines one or more CcInfo objects, except that all
# linker inputs owned by  owners in `old_owner_labels` are relinked and owned by the current target.
#
# This is useful in the "macro with proxy rule" pattern, as some rules upstream
# may expect they are depending directly on a target which generates linker inputs,
# as opposed to a proxy target which is a level of indirection to such a target.
def _cc_library_combiner_impl(ctx):
    old_owner_labels = []
    cc_infos = []
    for dep in ctx.attr.roots:
        old_owner_labels.append(dep.label)
        cc_infos.append(dep[CcInfo])
    for dep in ctx.attr.deps:
        old_owner_labels.append(dep.label)
        cc_info = dep[CcInfo]

        # do not propagate includes, hdrs, etc, already handled by roots
        cc_infos.append(CcInfo(linking_context = cc_info.linking_context))
    combined_info = cc_common.merge_cc_infos(cc_infos = cc_infos)

    objects_to_link = []

    # This is not ideal, as it flattens a depset.
    for old_linker_input in combined_info.linking_context.linker_inputs.to_list():
        if old_linker_input.owner in old_owner_labels:
            for lib in old_linker_input.libraries:
                # These objects will be recombined into the root archive.
                objects_to_link.extend(lib.objects)
        else:
            # Android macros don't handle transitive linker dependencies because
            # it's unsupported in legacy. We may want to change this going forward,
            # but for now it's good to validate that this invariant remains.
            fail("cc_static_library %s given transitive linker dependency from %s" % (ctx.label, old_linker_input.owner))

    cc_toolchain = find_cpp_toolchain(ctx)
    CPP_LINK_STATIC_LIBRARY_ACTION_NAME = "c++-link-static-library"
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features + ["linker_flags"],
    )

    output_file = ctx.actions.declare_file("lib" + ctx.label.name + ".a")
    linker_input = cc_common.create_linker_input(
        owner = ctx.label,
        libraries = depset(direct = [
            cc_common.create_library_to_link(
                actions = ctx.actions,
                feature_configuration = feature_configuration,
                cc_toolchain = cc_toolchain,
                static_library = output_file,
                objects = objects_to_link,
                alwayslink = ctx.attr.alwayslink,
            ),
        ]),
    )

    linking_context = cc_common.create_linking_context(linker_inputs = depset(direct = [linker_input]))

    archiver_path = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = CPP_LINK_STATIC_LIBRARY_ACTION_NAME,
    )
    archiver_variables = cc_common.create_link_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        output_file = output_file.path,
        is_using_linker = False,
    )
    command_line = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = CPP_LINK_STATIC_LIBRARY_ACTION_NAME,
        variables = archiver_variables,
    )
    args = ctx.actions.args()
    args.add_all(command_line)
    args.add_all(objects_to_link)

    ctx.actions.run(
        executable = archiver_path,
        arguments = [args],
        inputs = depset(
            direct = objects_to_link,
            transitive = [
                cc_toolchain.all_files,
            ],
        ),
        outputs = [output_file],
    )

    providers = [
        DefaultInfo(files = depset(direct = [output_file]), data_runfiles = ctx.runfiles(files = [output_file])),
        CcInfo(compilation_context = combined_info.compilation_context, linking_context = linking_context),
        CcStaticLibraryInfo(root_static_archive = output_file, objects = objects_to_link),
    ]

    if ctx.attr.tidy:
        cpp_srcs, cpp_hdrs = get_non_header_srcs(ctx.files.srcs_cpp, ctx.files.tidy_disabled_srcs)
        c_srcs, c_hdrs = get_non_header_srcs(ctx.files.srcs_c, ctx.files.tidy_disabled_srcs)
        hdrs = ctx.attr.hdrs + cpp_hdrs + c_hdrs
        cpp_tidy_outs = generate_clang_tidy_actions(
            ctx,
            ctx.attr.copts_cpp,
            ctx.attr.deps + ctx.attr.includes,
            cpp_srcs,
            hdrs,
            "c++",
            ctx.attr.tidy_flags,
            ctx.attr.tidy_checks,
            ctx.attr.tidy_checks_as_errors,
        )
        c_tidy_outs = generate_clang_tidy_actions(
            ctx,
            ctx.attr.copts_c,
            ctx.attr.deps + ctx.attr.includes,
            c_srcs,
            hdrs,
            "c",
            ctx.attr.tidy_flags,
            ctx.attr.tidy_checks,
            ctx.attr.tidy_checks_as_errors,
        )
        tidy_files = depset(cpp_tidy_outs + c_tidy_outs)
        providers.extend([
            OutputGroupInfo(
                _validation = tidy_files,
            ),
            ClangTidyInfo(
                tidy_files = tidy_files,
            ),
        ])

    return providers

# A rule which combines objects of oen or more cc_library targets into a single
# static linker input. This outputs a single archive file combining the objects
# of its direct deps, and propagates Cc providers describing that these objects
# should be linked for linking rules upstream.
# This rule is useful for maintaining the illusion that the target's deps are
# comprised by a single consistent rule:
#   - A single archive file is always output by this rule.
#   - A single linker input struct is always output by this rule, and it is 'owned'
#       by this rule.
_cc_library_combiner = rule(
    implementation = _cc_library_combiner_impl,
    attrs = {
        "roots": attr.label_list(providers = [CcInfo]),
        "deps": attr.label_list(providers = [CcInfo]),
        "runtime_deps": attr.label_list(
            providers = [CcInfo],
            doc = "Deps that should be installed along with this target. Read by the apex cc aspect.",
        ),
        "_cc_toolchain": attr.label(
            default = Label("@local_config_cc//:toolchain"),
            providers = [cc_common.CcToolchainInfo],
        ),
        "alwayslink": attr.bool(
            doc = """At link time, whether these libraries should be wrapped in
            the --whole_archive block. This causes all libraries in the static
            archive to be unconditionally linked, regardless of whether the
            symbols in these object files are being searched by the linker.""",
            default = False,
        ),

        # Clang-tidy attributes
        "tidy": attr.bool(),
        "srcs_cpp": attr.label_list(allow_files = True),
        "srcs_c": attr.label_list(allow_files = True),
        "copts_cpp": attr.string_list(),
        "copts_c": attr.string_list(),
        "hdrs": attr.label_list(allow_files = True),
        "includes": attr.label_list(),
        "tidy_checks": attr.string_list(),
        "tidy_checks_as_errors": attr.string_list(),
        "tidy_flags": attr.string_list(),
        "tidy_disabled_srcs": attr.label_list(allow_files = True),
        "_clang_tidy_sh": attr.label(
            default = Label("@//prebuilts/clang/host/linux-x86:clang-tidy.sh"),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            doc = "The clang tidy shell wrapper",
        ),
        "_clang_tidy": attr.label(
            default = Label("@//prebuilts/clang/host/linux-x86:clang-tidy"),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            doc = "The clang tidy executable",
        ),
        "_clang_tidy_real": attr.label(
            default = Label("@//prebuilts/clang/host/linux-x86:clang-tidy.real"),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
        "_with_tidy_flags": attr.label(
            default = "//build/bazel/flags/cc/tidy:with_tidy_flags",
        ),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    provides = [CcInfo],
    fragments = ["cpp"],
)

def _cc_includes_impl(ctx):
    return [create_ccinfo_for_includes(
        ctx,
        includes = ctx.attr.includes,
        absolute_includes = ctx.attr.absolute_includes,
        system_includes = ctx.attr.system_includes,
        deps = ctx.attr.deps,
    )]

# Bazel's native cc_library rule supports specifying include paths two ways:
# 1. non-exported includes can be specified via copts attribute
# 2. exported -isystem includes can be specified via includes attribute
#
# In order to guarantee a correct inclusion search order, we need to export
# includes paths for both -I and -isystem; however, there is no native Bazel
# support to export both of these, this rule provides a CcInfo to propagate the
# given package-relative include/system include paths as exec root relative
# include/system include paths.
_cc_includes = rule(
    implementation = _cc_includes_impl,
    attrs = {
        "absolute_includes": attr.string_list(doc = "List of exec-root relative or absolute search paths for headers, usually passed with -I"),
        "includes": attr.string_list(doc = "Package-relative list of search paths for headers, usually passed with -I"),
        "system_includes": attr.string_list(doc = "Package-relative list of search paths for headers, usually passed with -isystem"),
        "deps": attr.label_list(doc = "Re-propagates the includes obtained from these dependencies.", providers = [CcInfo]),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
    provides = [CcInfo],
)
