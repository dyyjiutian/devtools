"""Macros that expand OS-profile × module suites into sh_test targets."""

load("@rules_shell//shell:sh_test.bzl", "sh_test")

def devtools_module_tests(
        name,
        suite,
        module_root,
        module_data,
        profiles,
        docker_profiles = [],
        size = "small"):
    """Create L1 host profile tests and optional L2 Docker tests.

    Args:
      name: Module short name (e.g. \"git\", \"tmux\").
      suite: Label of the suite shell script.
      module_root: Label of a file inside the module directory (usually setup.sh).
      module_data: Extra labels needed at runtime (scripts, configs, bins).
      profiles: OS profiles for L1 host tests.
      docker_profiles: Subset of profiles for L2 Docker tests.
      size: Bazel test size.
    """
    common_data = [
        "//testing:lib_files",
        suite,
        module_root,
    ] + module_data

    for profile in profiles:
        sh_test(
            name = "%s_%s_test" % (name, profile),
            srcs = ["//testing:lib/run_module_test.sh"],
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
        )

    for profile in docker_profiles:
        sh_test(
            name = "%s_%s_docker_test" % (name, profile),
            srcs = ["//testing:docker/run_in_docker.sh"],
            args = [
                "--profile",
                profile,
                "--suite",
                "$(rootpath %s)" % suite,
                "--module-root",
                "$(rootpath %s)" % module_root,
            ],
            data = common_data + [
                "//testing:docker_files",
            ],
            size = "large",
            tags = [
                "requires-docker",
                "no-sandbox",
                "requires-network",
                "local",
            ],
        )
