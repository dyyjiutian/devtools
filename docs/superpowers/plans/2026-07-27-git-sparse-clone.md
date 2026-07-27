# git sparse-clone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add portable `git sparse-clone` under `tools/git` for cone-mode sparse clone + append.

**Architecture:** Single self-contained bash script `bin/git-sparse-clone`, installed like other git subcommands; tests use local bare repos inside the existing Bazel module suite.

**Tech Stack:** Bash, Git ≥ 2.25 (`clone --sparse`, `sparse-checkout` cone), existing `devtools_module_tests`.

## Global Constraints

- Portable script in `tools/git/bin/` (survives repo removal after install).
- Cone mode only; reject glob / `!` paths.
- Default depth `1`, default `--filter=blob:none`.
- No paths ⇒ root files only; `--append` needs ≥1 path.
- Bazel tests must pass on `macos` and `linux_centos` profiles.
- Do not commit secrets or machine-specific paths.

## File Structure

| File | Responsibility |
|------|----------------|
| `tools/git/bin/git-sparse-clone` | CLI + clone/append orchestration |
| `tools/git/man/man1/git-sparse-clone.1` | man page |
| `tools/git/scripts/sub-command.sh` | install new command + man |
| `tools/git/setup.sh` | help text lists new subcommand |
| `tools/git/README.md` | user docs + Issues if fixing gaps |
| `tools/git/tests/git_suite.sh` | regression tests |

---

### Task 1: Help / validation + failing tests

**Files:**
- Create: `tools/git/bin/git-sparse-clone` (stub with parse/help/validation)
- Modify: `tools/git/tests/git_suite.sh`
- Modify: `tools/git/scripts/sub-command.sh` (COMMANDS/MANPAGES + help)

- [ ] **Step 1: Add suite tests for help, glob reject, append-without-paths**

```bash
SPARSE_CLONE="$MODULE_ROOT/bin/git-sparse-clone"

test_sparse_clone_help() {
  local out
  out="$(bash "$SPARSE_CLONE" --help 2>&1)"
  assert_contains "$out" "sparse-clone" "help mentions sparse-clone"
  assert_contains "$out" "--append" "help mentions append"
  pass "git sparse-clone --help ($DEVTOOLS_TEST_PROFILE)"
}

test_sparse_clone_rejects_glob() {
  local rc=0
  bash "$SPARSE_CLONE" --dry-run "https://example.com/repo.git" 'src/**' >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "glob path should fail"
  pass "git sparse-clone rejects glob ($DEVTOOLS_TEST_PROFILE)"
}

test_sparse_clone_append_requires_paths() {
  local rc=0
  bash "$SPARSE_CLONE" --append >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "append without paths should fail"
  pass "git sparse-clone append requires paths ($DEVTOOLS_TEST_PROFILE)"
}
```

- [ ] **Step 2: Implement stub `git-sparse-clone` with usage + arg parse + path validation only**

- [ ] **Step 3: Wire `git-sparse-clone` into `sub-command.sh` COMMANDS/MANPAGES/usage**

- [ ] **Step 4: Run suite (or at least help/validation cases) and fix until pass**

---

### Task 2: Clone + append implementation + integration tests

**Files:**
- Modify: `tools/git/bin/git-sparse-clone`
- Modify: `tools/git/tests/git_suite.sh`

- [ ] **Step 1: Add local-bare-repo integration tests**

Helper creates a bare repo with `README`, `devtools/a.txt`, `scripts/b.txt`, then:

- no-path clone → `README` present, `devtools/` absent
- path clone `devtools` → `devtools/a.txt` present, `scripts/` absent
- append `scripts` → both present
- `--dry-run` → target dir not created

- [ ] **Step 2: Implement `do_clone` and `do_append` in `git-sparse-clone`**

Clone shape:

```bash
git clone --filter=blob:none --sparse --depth 1 [--branch B] <url> <dir>
# optional: git sparse-checkout set --cone -- paths...
# optional: checkout commit
```

Append shape:

```bash
git -C "$repo" sparse-checkout add -- paths...
```

- [ ] **Step 3: Run `bazel test //tools/git/...` (or suite via existing runner) on available profiles**

---

### Task 3: Man page + README + setup help

**Files:**
- Create: `tools/git/man/man1/git-sparse-clone.1`
- Modify: `tools/git/README.md`
- Modify: `tools/git/setup.sh` (help subcommand list)

- [ ] **Step 1: Write man page matching CLI**
- [ ] **Step 2: Document in README (table + examples)**
- [ ] **Step 3: Update setup.sh help text**
- [ ] **Step 4: `bash -n` on scripts; re-run git module tests**

---

## Spec coverage check

| Spec requirement | Task |
|------------------|------|
| Positional URL + paths CLI | 1–2 |
| Defaults: depth 1, blob filter, root-only | 2 |
| `--dir/--branch/--commit/--depth/--no-filter/--force/--dry-run` | 2 |
| `--append [--dir]` | 2 |
| Reject glob / `!` | 1 |
| Install via sub-command.sh + man | 1, 3 |
| README / setup help | 3 |
| Bazel macos + linux_centos | 2–3 |
