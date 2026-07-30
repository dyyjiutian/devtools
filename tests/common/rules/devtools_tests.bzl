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
        tags = tags + ["unit"],
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
                "integration",
                "compatibility",
                "profile-%s" % profile,
                "requires-docker",
                "no-sandbox",
                "requires-network",
                "local",
            ],
        )
