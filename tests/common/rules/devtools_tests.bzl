"""Macros that expand OS-profile × module suites into sh_test targets."""

load("@rules_shell//shell:sh_test.bzl", "sh_test")

def devtools_unit_test(
        name,
        suite,
        data = [],
        tags = [],
        size = "small"):
    """Create a hermetic shell unit test.

    Args:
      name: Bazel target name.
      suite: Label of the shell suite.
      data: Extra labels needed by the suite.
      tags: Extra tags added to the test.
      size: Bazel test size.
    """
    sh_test(
        name = name,
        srcs = ["//tests/common:lib/run_unit_test.sh"],
        args = [
            "--suite",
            "$(rootpath %s)" % suite,
        ],
        data = [
            "//tests/common:lib_files",
            suite,
        ] + data,
        size = size,
        tags = tags + [
            "l1",
            "unit",
        ],
    )

def devtools_module_tests(
        name,
        suite,
        module_root,
        module_data,
        profiles,
        docker_profiles = [],
        tags = [],
        size = "small"):
    """Create L1 host profile tests and optional L2 Docker tests.

    Args:
      name: Module short name (e.g. \"git\", \"tmux\").
      suite: Label of the suite shell script.
      module_root: Label of a file inside the module directory (usually setup.sh).
      module_data: Extra labels needed at runtime (scripts, configs, bins).
      profiles: OS profiles for L1 host tests.
      docker_profiles: Subset of profiles for L2 Docker tests.
      tags: Extra tags added to every generated test.
      size: Bazel test size.
    """
    common_data = [
        "//tests/common:lib_files",
        suite,
        module_root,
    ] + module_data

    for profile in profiles:
        sh_test(
            name = "%s_%s_test" % (name, profile),
            srcs = ["//tests/common:lib/run_module_test.sh"],
            args = [
                "--profile",
                profile,
                "--suite",
                "$(rootpath %s)" % suite,
                "--module-root",
                "$(rootpath %s)" % module_root,
            ],
            data = common_data,
            size = size,
            tags = tags + [
                "l1",
                "integration",
                "compatibility",
                "profile-%s" % profile,
            ],
        )

    for profile in docker_profiles:
        sh_test(
            name = "%s_%s_docker_test" % (name, profile),
            srcs = ["//tests/common:docker/run_in_docker.sh"],
            args = [
                "--profile",
                profile,
                "--suite",
                "$(rootpath %s)" % suite,
                "--module-root",
                "$(rootpath %s)" % module_root,
            ],
            data = common_data + [
                "//tests/common:docker_files",
            ],
            size = "large",
            tags = tags + [
                "l2",
                "integration",
                "compatibility",
                "profile-%s" % profile,
                "requires-docker",
                "no-sandbox",
                "requires-network",
                "local",
            ],
        )

def devtools_e2e_tests(
        name,
        suite,
        module_root,
        module_data,
        profiles,
        setup_args = [],
        tags = [],
        size = "enormous"):
    """Create official-image E2E tests that run real setup.sh (no OS fakes).

    Args:
      name: Short name (e.g. \"tmux_ops\").
      suite: Label of the E2E ops suite.
      module_root: Label of a file inside the module directory (usually setup.sh).
      module_data: Extra labels needed at runtime.
      profiles: Linux profiles with official Docker images.
      setup_args: Extra flags forwarded to setup.sh (e.g. [\"--upgrade\"]).
      tags: Extra tags added to every generated test.
      size: Bazel test size (default enormous; real installs are slow).
    """
    setup_arg_flags = []
    for arg in setup_args:
        setup_arg_flags.extend(["--setup-arg", arg])

    for profile in profiles:
        sh_test(
            name = "%s_%s_e2e_test" % (name, profile),
            srcs = ["//tests/common:docker/run_e2e_in_docker.sh"],
            args = [
                "--profile",
                profile,
                "--suite",
                "$(rootpath %s)" % suite,
                "--module-root",
                "$(rootpath %s)" % module_root,
            ] + setup_arg_flags,
            data = [
                "//tests/common:lib_files",
                "//tests/common:docker_files",
                suite,
                module_root,
            ] + module_data,
            size = size,
            tags = tags + [
                "l3",
                "e2e",
                "compatibility",
                "profile-%s" % profile,
                "requires-docker",
                "no-sandbox",
                "requires-network",
                "local",
            ],
        )

def devtools_host_e2e_tests(
        name,
        suite,
        module_root,
        module_data,
        setup_args = [],
        tags = [],
        size = "enormous"):
    """Create a Darwin host E2E test (no Docker; used on GitHub macos-26).

    Args:
      name: Short name (e.g. \"tmux_ops\").
      suite: Label of the E2E ops suite.
      module_root: Label of a file inside the module directory (usually setup.sh).
      module_data: Extra labels needed at runtime.
      setup_args: Extra flags forwarded to setup.sh.
      tags: Extra tags added to the test.
      size: Bazel test size (default enormous; real installs are slow).
    """
    setup_arg_flags = []
    for arg in setup_args:
        setup_arg_flags.extend(["--setup-arg", arg])

    sh_test(
        name = "%s_macos_e2e_test" % name,
        srcs = ["//tests/common:lib/run_e2e_test.sh"],
        args = [
            "--suite",
            "$(rootpath %s)" % suite,
            "--module-root",
            "$(rootpath %s)" % module_root,
        ] + setup_arg_flags,
        data = [
            "//tests/common:lib_files",
            suite,
            module_root,
        ] + module_data,
        env = {
            "DEVTOOLS_E2E_REQUIRE_DARWIN": "1",
        },
        size = size,
        tags = tags + [
            "l3",
            "e2e",
            "compatibility",
            "profile-macos",
            "requires-macos",
            "requires-network",
            "no-sandbox",
            "local",
        ],
    )
