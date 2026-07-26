# testing/

Shared harness for OS-profile × module setup-script tests.

- **L1** `lib/run_module_test.sh` — host hermetic PATH + profile fakes
- **L2** `docker/run_in_docker.sh` — same suites inside Ubuntu/CentOS images
- **Rules** `rules/devtools_tests.bzl` — `devtools_module_tests()` macro

See `docs/superpowers/specs/2026-07-25-bazel-matrix-tests-design.md`.
