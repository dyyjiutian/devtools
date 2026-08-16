# Bats tests for os/macos/setup.sh (safe: syntax + CLI; no install).
# SETUP_SH is exported by run_bats.sh (bazel test) from runfiles paths.
# 本地手动跑（已安装 bats）: export SETUP_SH="$PWD/setup.sh" && bats setup.bats

@test "setup.sh passes bash -n" {
  run bash -n "$SETUP_SH"
  [ "$status" -eq 0 ]
}

# @test 名称仅用 ASCII：部分环境下含中文的测试名会导致 bats 解析失败
@test "setup.sh --help exits 0 and prints usage (Chinese heading)" {
  run "$SETUP_SH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"用法"* ]]
}

@test "setup.sh rejects unknown flag with exit 1" {
  run "$SETUP_SH" --not-a-real-flag-xyz 2>/dev/null
  [ "$status" -eq 1 ]
}

@test "packages.list satisfies shared manifest contract" {
  run bash -c '
    source "$1"
    packages_list_has "$2" git
    packages_list_has "$2" rg
    packages_list_has "$2" glow
    [[ "$(packages_list_brew_formula rg)" == "ripgrep" ]]
  ' _ "$PACKAGES_LIB" "$PACKAGES_LIST"
  [ "$status" -eq 0 ]
}
