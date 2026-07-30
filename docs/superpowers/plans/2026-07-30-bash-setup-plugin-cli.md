# bash setup plugin CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `shell/bash/setup.sh` into a subcommand CLI supporting full install, per-plugin install, and `list` with install status.

**Architecture:** Keep a single `setup.sh`. Add a plugin registry (id → description / status check / install fn), parse global flags + subcommands, dispatch to `cmd_install` / `cmd_list`. Always rewrite the full `.bashrc` marker block; write `starship.toml` only on full install or when `starship` is among selected plugins. Dry-run short flag becomes `-n`.

**Tech Stack:** Bash (`set -euo pipefail`), existing fake-PATH patterns in `tests/linux_setup_scripts_test.sh`, `bash -n`.

## Global Constraints

- Subcommands: `install` (default when omitted), `list`.
- Plugin IDs: `blesh` (alias `ble.sh`), `zoxide`, `fzf`, `starship`.
- Single-plugin install still writes the **full** `.bashrc` config block.
- `list` prints name + description + `[installed]` / `[missing]`.
- Dry-run: `-n, --dry-run` only (remove `-d`).
- Do not split into `lib/`; do not add uninstall; do not change zsh setup.
- Preserve ble.sh `--noattach --noinputrc` and Linux cache fallbacks.
- Existing starship-cache / fzf-retry cases in `tests/linux_setup_scripts_test.sh` must keep passing (they call `setup.sh` with no args).

## File Structure

| File | Responsibility |
|------|----------------|
| `shell/bash/setup.sh` | CLI parse, plugin registry, install/list, bashrc + starship config |
| `shell/bash/README.md` | User-facing usage for subcommands / `-n` |
| `tests/linux_setup_scripts_test.sh` | Regression for list / single install / unknown plugin / `-n` |
| Spec (read-only): `docs/superpowers/specs/2026-07-30-bash-setup-plugin-cli-design.md` | Behavior source of truth |

---

### Task 1: CLI parse, help, list status, failing tests

**Files:**
- Modify: `tests/linux_setup_scripts_test.sh`
- Modify: `shell/bash/setup.sh`

**Interfaces:**
- Produces:
  - `show_help` documents `install` / `list` / `-n`
  - `cmd_list` prints four plugin rows with `[installed]` or `[missing]`
  - `parse_args` accepts `-n|--dry-run`, `-h|--help`, subcommands; rejects unknown plugins with exit ≠ 0
  - Plugin status helpers: `plugin_is_installed <id>` → 0 if installed

- [ ] **Step 1: Append failing CLI tests to `tests/linux_setup_scripts_test.sh`**

Add near the end (before any final success echo if present; otherwise append):

```bash
# --- shell/bash setup.sh plugin CLI ---
bash -n "$ROOT/shell/bash/setup.sh" || fail "bash -n shell/bash/setup.sh"

cli_help="$TMP_DIR/bash-cli-help.log"
bash "$ROOT/shell/bash/setup.sh" --help >"$cli_help" 2>&1 || fail "setup.sh --help failed"
assert_contains "$cli_help" "install"
assert_contains "$cli_help" "list"
assert_contains "$cli_help" "-n"
assert_not_contains "$cli_help" "-d, --dry-run"

cli_list_home="$TMP_DIR/bash-list-home"
mkdir -p "$cli_list_home/.local/share/blesh" "$cli_list_home/.local/bin"
touch "$cli_list_home/.local/share/blesh/ble.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$cli_list_home/.local/bin/zoxide"
chmod +x "$cli_list_home/.local/bin/zoxide"
# fzf and starship intentionally missing
cli_list="$TMP_DIR/bash-cli-list.log"
PATH="$cli_list_home/.local/bin:/usr/bin:/bin" HOME="$cli_list_home" \
  bash "$ROOT/shell/bash/setup.sh" list >"$cli_list" 2>&1 ||
  fail "setup.sh list failed: $(cat "$cli_list")"
assert_contains "$cli_list" "blesh"
assert_contains "$cli_list" "zoxide"
assert_contains "$cli_list" "fzf"
assert_contains "$cli_list" "starship"
assert_contains "$cli_list" "[installed]"
assert_contains "$cli_list" "[missing]"
grep -E 'blesh[[:space:]].*\[installed\]' "$cli_list" >/dev/null ||
  fail "blesh should be installed in list output"
grep -E 'zoxide[[:space:]].*\[installed\]' "$cli_list" >/dev/null ||
  fail "zoxide should be installed in list output"
grep -E 'fzf[[:space:]].*\[missing\]' "$cli_list" >/dev/null ||
  fail "fzf should be missing in list output"
grep -E 'starship[[:space:]].*\[missing\]' "$cli_list" >/dev/null ||
  fail "starship should be missing in list output"

cli_unknown_rc=0
bash "$ROOT/shell/bash/setup.sh" install nope >"$TMP_DIR/bash-cli-unknown.log" 2>&1 || cli_unknown_rc=$?
[[ "$cli_unknown_rc" -ne 0 ]] || fail "unknown plugin should fail"
assert_contains "$TMP_DIR/bash-cli-unknown.log" "list"

cli_dry="$TMP_DIR/bash-cli-dry.log"
HOME="$TMP_DIR/bash-dry-home" mkdir -p "$TMP_DIR/bash-dry-home"
HOME="$TMP_DIR/bash-dry-home" PATH="/usr/bin:/bin" \
  bash "$ROOT/shell/bash/setup.sh" install -n >"$cli_dry" 2>&1 ||
  fail "setup.sh install -n failed: $(cat "$cli_dry")"
assert_contains "$cli_dry" "试运行"
[[ ! -f "$TMP_DIR/bash-dry-home/.bashrc" ]] ||
  fail "dry-run must not create .bashrc when it did not exist"
```

- [ ] **Step 2: Run tests to verify new cases fail**

Run: `bash tests/linux_setup_scripts_test.sh`
Expected: FAIL on help (`install`/`list`/`-n`) and/or `list` subcommand unknown.

- [ ] **Step 3: Implement argument parsing + help + list (minimal; install still full-only OK)**

Replace the top-level `while` parse + bare `main` call with structures like:

```bash
PLUGIN_IDS=(blesh zoxide fzf starship)

plugin_description() {
  case "$1" in
    blesh)    echo "命令历史自动建议 + 实时语法高亮" ;;
    zoxide)   echo "智能目录跳转" ;;
    fzf)      echo "模糊搜索" ;;
    starship) echo "跨 shell 提示符" ;;
    *) return 1 ;;
  esac
}

normalize_plugin_id() {
  case "$1" in
    ble.sh|blesh) echo "blesh" ;;
    zoxide|fzf|starship) echo "$1" ;;
    *) return 1 ;;
  esac
}

plugin_is_installed() {
  case "$1" in
    blesh)
      if [[ "$OS" == "Darwin" ]]; then
        local brew_prefix; brew_prefix="$(brew --prefix 2>/dev/null || true)"
        [[ -n "$brew_prefix" && -f "${brew_prefix}/share/blesh/ble.sh" ]]
      else
        [[ -f "$HOME/.local/share/blesh/ble.sh" ]]
      fi
      ;;
    zoxide)   command -v zoxide &>/dev/null ;;
    fzf)      command -v fzf &>/dev/null ;;
    starship) command -v starship &>/dev/null ;;
    *) return 1 ;;
  esac
}

cmd_list() {
  local id desc status
  for id in "${PLUGIN_IDS[@]}"; do
    desc="$(plugin_description "$id")"
    if plugin_is_installed "$id"; then status="[installed]"; else status="[missing]"; fi
    printf '%-10s %-36s %s\n' "$id" "$desc" "$status"
  done
}
```

Update `show_help` to document subcommands and `-n, --dry-run` (remove `-d`).

Parse loop sketch:

```bash
COMMAND=""
SELECTED_PLUGINS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    -n|--dry-run) DRY_RUN=true; shift ;;
    install|list)
      [[ -z "$COMMAND" ]] || { error "重复子命令: $1"; exit 1; }
      COMMAND="$1"; shift
      ;;
    -*)
      error "未知选项: $1"; show_help; exit 1
      ;;
    *)
      if [[ -z "$COMMAND" || "$COMMAND" == "install" ]]; then
        COMMAND="${COMMAND:-install}"
        local pid
        pid="$(normalize_plugin_id "$1")" || { error "未知插件: $1（运行: $(basename "$0") list）"; exit 1; }
        SELECTED_PLUGINS+=("$pid")
        shift
      else
        error "list 不接受额外参数: $1"; exit 1
      fi
      ;;
  esac
done

COMMAND="${COMMAND:-install}"
```

Wire dispatch at bottom:

```bash
case "$COMMAND" in
  list) cmd_list ;;
  install) main "${SELECTED_PLUGINS[@]}" ;;  # Task 2 will specialize
  *) error "未知命令: $COMMAND"; exit 1 ;;
esac
```

For this task, `main` may ignore plugin args and still install all (existing behavior) so Step 4 can pass list/help/dry-run/unknown; single-plugin selectivity comes in Task 2. Alternatively leave `main` unchanged and call it only when `SELECTED_PLUGINS` is empty; if non-empty, temporarily `error "尚未实现"` — prefer keeping full install working for empty selection so existing tests pass.

- [ ] **Step 4: Re-run tests**

Run: `bash tests/linux_setup_scripts_test.sh`
Expected: PASS for help / list / unknown / `-n`; existing starship/fzf cases still PASS. Single-plugin selectivity tests are added in Task 2 (not yet).

- [ ] **Step 5: Commit**

```bash
git add shell/bash/setup.sh tests/linux_setup_scripts_test.sh
git commit -m "$(cat <<'EOF'
feat(bash): add install/list CLI and -n dry-run

EOF
)"
```

---

### Task 2: Per-plugin install dispatch + bashrc/starship rules

**Files:**
- Modify: `shell/bash/setup.sh`
- Modify: `tests/linux_setup_scripts_test.sh`
- Modify: `shell/bash/README.md`

**Interfaces:**
- Consumes: `PLUGIN_IDS`, `normalize_plugin_id`, `SELECTED_PLUGINS`, `DRY_RUN`, existing `_install_linux_*` / brew install paths
- Produces:
  - `install_plugin <id>` — OS-aware single plugin install
  - `cmd_install [plugin_ids...]` — empty ⇒ all; always `configure_bashrc`; `configure_starship_config` iff full install or `starship` selected

- [ ] **Step 1: Add failing single-plugin install test**

```bash
# install fzf only must not invoke zoxide online installer (curl) when zoxide missing
single_home="$TMP_DIR/bash-single-home"
single_bin="$TMP_DIR/bash-single-bin"
mkdir -p "$single_home/.local/share/blesh" "$single_home/.fzf" "$single_bin"
touch "$single_home/.local/share/blesh/ble.sh"
printf '#!/usr/bin/env bash\ntouch "$FZF_INSTALL_MARKER"\n' > "$single_home/.fzf/install"
chmod +x "$single_home/.fzf/install"
printf '#!/usr/bin/env bash\nif [[ "$1" == "clone" ]]; then touch "$FZF_CLONE_MARKER"; exit 99; fi\nexit 0\n' > "$single_bin/git"
cat > "$single_bin/curl" <<'EOF'
#!/usr/bin/env bash
touch "$CURL_CALLED_MARKER"
exit 97
EOF
chmod +x "$single_bin/git" "$single_bin/curl"

FZF_INSTALL_MARKER="$TMP_DIR/bash-single-fzf-install" \
FZF_CLONE_MARKER="$TMP_DIR/bash-single-fzf-clone" \
CURL_CALLED_MARKER="$TMP_DIR/bash-single-curl" \
PATH="$single_bin:/usr/bin:/bin" HOME="$single_home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" \
  bash "$ROOT/shell/bash/setup.sh" install fzf >"$TMP_DIR/bash-single.log" 2>&1 ||
  fail "install fzf failed: $(cat "$TMP_DIR/bash-single.log")"
assert_file "$TMP_DIR/bash-single-fzf-install"
[[ ! -e "$TMP_DIR/bash-single-curl" ]] || fail "install fzf must not curl-install zoxide/starship"
assert_contains "$single_home/.bashrc" "Lightweight Bash Plugins"
# starship.toml must NOT be written for fzf-only install
[[ ! -f "$single_home/.config/starship.toml" ]] ||
  fail "fzf-only install must not write starship.toml"

# alias ble.sh
alias_rc=0
PATH="$single_bin:/usr/bin:/bin" HOME="$single_home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" \
  bash "$ROOT/shell/bash/setup.sh" install ble.sh -n >"$TMP_DIR/bash-alias.log" 2>&1 || alias_rc=$?
[[ "$alias_rc" -eq 0 ]] || fail "ble.sh alias dry-run failed: $(cat "$TMP_DIR/bash-alias.log")"
```

- [ ] **Step 2: Run test — expect FAIL** on curl being called or starship.toml written (current full install).

- [ ] **Step 3: Implement per-plugin install + `cmd_install`**

```bash
_install_macos_plugin() {
  local brew_name="$1"
  if brew list "$brew_name" &>/dev/null 2>&1; then
    success "$brew_name 已安装，跳过"
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[试运行] brew install $brew_name"
    return
  fi
  info "安装 $brew_name ..."
  brew install "$brew_name"
  success "$brew_name 安装完成"
}

install_plugin() {
  local id="$1"
  case "$OS" in
    Darwin)
      case "$id" in
        blesh)    _install_macos_plugin blesh ;;
        zoxide)   _install_macos_plugin zoxide ;;
        fzf)      _install_macos_plugin fzf ;;
        starship) _install_macos_plugin starship ;;
      esac
      ;;
    Linux)
      mkdir -p "$LINUX_PLUGIN_DIR" "$LOCAL_BIN_DIR"
      case "$id" in
        blesh)    _install_linux_blesh ;;
        zoxide)   _install_linux_zoxide ;;
        fzf)      _install_linux_fzf ;;
        starship) _install_linux_starship ;;
      esac
      ;;
    *) error "不支持的操作系统: $OS"; exit 1 ;;
  esac
}

cmd_install() {
  local plugins=("$@")
  local id want_starship_config=false
  if [[ ${#plugins[@]} -eq 0 ]]; then
    plugins=("${PLUGIN_IDS[@]}")
    want_starship_config=true
  else
    for id in "${plugins[@]}"; do
      [[ "$id" == "starship" ]] && want_starship_config=true
    done
  fi

  info "轻量级 Bash 插件安装脚本"
  info "运行模式: $([[ "$DRY_RUN" == "true" ]] && echo "试运行" || echo "实际执行")"
  info "操作系统: $OS"
  info "插件: ${plugins[*]}"
  echo ""

  if [[ "$OS" == "Darwin" ]] && ! command -v brew &>/dev/null; then
    error "Homebrew 未安装，请先安装: https://brew.sh"
    exit 1
  fi
  if [[ "$OS" == "Linux" ]]; then
    command -v git &>/dev/null || { error "需要 git，请先安装"; exit 1; }
    command -v curl &>/dev/null || { error "需要 curl，请先安装"; exit 1; }
  fi

  step "安装插件..."
  for id in "${plugins[@]}"; do
    install_plugin "$id"
  done

  echo ""
  configure_bashrc

  if [[ "$want_starship_config" == "true" ]]; then
    echo ""
    configure_starship_config
  fi

  echo ""
  success "安装完成！"
  # keep existing post-install hints (source bashrc / shortcuts); OK to always print
}

# remove old install_macos / install_linux orchestration (keep _install_linux_* helpers)
# bottom dispatch:
case "$COMMAND" in
  list) cmd_list ;;
  install) cmd_install "${SELECTED_PLUGINS[@]}" ;;
esac
```

Ensure Linux `install_plugin` for a single tool still `mkdir -p` plugin/bin dirs. Keep `generate_bashrc_config` unchanged (full block always).

- [ ] **Step 4: Update `shell/bash/README.md`**

```markdown
# Bash 配置

安装 ble.sh、zoxide、fzf 和 Starship，并幂等写入 ~/.bashrc。

~~~bash
bash shell/bash/setup.sh --help
bash shell/bash/setup.sh              # 完整安装
bash shell/bash/setup.sh install      # 同上
bash shell/bash/setup.sh install fzf  # 只装 fzf（仍写入完整 bashrc 配置块）
bash shell/bash/setup.sh list         # 列举插件与本机状态
bash shell/bash/setup.sh install -n   # 试运行
~~~

插件 ID：`blesh`（别名 `ble.sh`）、`zoxide`、`fzf`、`starship`。

Linux 安装优先使用 cache/ 中的二进制缓存。
```

Keep the existing Issues section intact.

- [ ] **Step 5: Run full regression**

```bash
bash -n shell/bash/setup.sh
bash tests/linux_setup_scripts_test.sh
```

Expected: all PASS (existing starship cache + fzf retry + new CLI + single fzf).

- [ ] **Step 6: Commit**

```bash
git add shell/bash/setup.sh shell/bash/README.md tests/linux_setup_scripts_test.sh
git commit -m "$(cat <<'EOF'
feat(bash): support per-plugin install via setup.sh

EOF
)"
```

---

## Self-Review Checklist (author)

1. **Spec coverage:** install default / install all / install N plugins / list+status / `-n` / full bashrc always / starship.toml only when full or starship selected / alias `ble.sh` / unknown plugin / README / tests — each mapped to Task 1 or 2.
2. **Placeholders:** none; code sketches are concrete.
3. **Consistency:** dry-run is `-n` everywhere; plugin IDs match spec; existing no-arg invocations remain full install.
