# Bazel Build System for DevTools

This repository uses Bazel 9.0.0 with bzlmod for building and packaging configuration files.

## Quick Start

### Install Bazel

```bash
# Using Homebrew (macOS)
brew install bazelisk

# Or using the official installer
curl -Lo bazel https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64
chmod +x bazel
sudo mv bazel /usr/local/bin/
```

### Build Everything

```bash
# Build all targets
bazel build //...

# Or use Make
make build
```

### Run Tests

```bash
# Run all tests
bazel test //...

# Run shellcheck on all scripts
bazel test //:shellcheck_all

# Run linting
make lint
```

### Create Distribution Packages

```bash
# Create a complete distribution archive
bazel build //:devtools_distribution

# The archive will be at:
# bazel-bin/devtools_distribution.tar.gz
```

## Bazel Targets

### Root Targets

| Target | Description |
|--------|-------------|
| `//:devtools_distribution` | Complete distribution archive (.tar.gz) |
| `//:os_scripts` | OS setup scripts package |
| `//:terminal_configs` | Terminal configurations package |
| `//:editor_configs` | Editor configurations package |
| `//:vcs_scripts` | VCS utilities package |
| `//:shellcheck_all` | Lint all shell scripts |
| `//:buildifier` | Format all BUILD files |

### Package Structure

```
//                      # Root BUILD file
├── agents/              # Agent configuration (Claude)
├── editors/            # Editor configurations (Cursor)
├── os/                 # OS setup scripts (macOS, Linux)
├── terminal/           # Terminal configurations
│   ├── ghostty/
│   ├── iterm2/
│   ├── nvim/
│   ├── oh-my-zsh/
│   └── vim/
├── vcs/                # VCS utilities (Git)
└── rules/              # Custom Bazel rules
    └── lint/           # Linting rules and configs
```

## Development Commands

```bash
# Format all BUILD files
bazel run //:buildifier

# Check BUILD file format
bazel run //:buildifier_check

# Sync MODULE dependencies
bazel mod tidy

# Query available targets
bazel query "//..." | head -20

# Clean build outputs
bazel clean

# Show build configuration
bazel info
```

## Bazel Configuration

### Key Files

| File | Purpose |
|------|---------|
| `.bazelversion` | Specifies Bazel version (9.0.0) |
| `MODULE.bazel` | Module dependencies (bzlmod) |
| `.bazelrc` | Bazel build configuration |
| `BUILD.bazel` | Build targets |

### Build Flags

The `.bazelrc` file configures:
- Platform detection (macOS/Linux)
- Caching (disk cache in `~/.cache/bazel-disk-cache`)
- Performance optimizations
- CI settings

### Custom Rules

#### shell_script_package

Packages shell scripts for distribution:

```starlark
shell_script_package(
    name = "my_scripts",
    srcs = ["//path:to_scripts"],
    package_name = "scripts",
)
```

#### config_package

Packages configuration files:

```starlark
config_package(
    name = "my_configs",
    srcs = ["//path:to_configs"],
    package_name = "configs",
)
```

## Shellcheck Configuration

Shell scripts are linted with [shellcheck](https://github.com/koalaman/shellcheck) using the configuration in `rules/lint/.shellcheckrc`.

Disabled checks for setup scripts:
- SC1090/SC1091: Can't follow non-constant source
- SC2155: Declare and assign separately
- SC2034: Variable appears unused
- SC2181: Check exit code directly
- SC2206: Quote to prevent word splitting
- SC2129: Multiple redirects
- SC2001: sed vs parameter substitution

## CI Integration

Example GitHub Actions workflow:

```yaml
name: Build
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: bazelbuild/setup-bazelisk@v3
      - run: bazel build //...
      - run: bazel test //...
      - run: bazel test //:shellcheck_all
```

## Useful Resources

- [Bazel Documentation](https://bazel.build/docs)
- [bzlmod Guide](https://bazel.build/external/overview)
- [rules_pkg](https://github.com/bazelbuild/rules_pkg)
- [ShellCheck](https://www.shellcheck.net/)
