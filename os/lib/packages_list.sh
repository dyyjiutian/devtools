#!/usr/bin/env bash
# Shared packages.list parser for os/*/setup*.sh
#
# Format (whitespace-separated, # comments and blank lines ignored):
#   name  version  source  kind  tags
#
# kind:  cli | tui | gui
# tags:  comma-separated purposes, e.g. productivity,diagnostic,dev,ops,shell
#
# Optional filters (set by setup scripts before foreach/check):
#   PACKAGES_FILTER_KIND=cli
#   PACKAGES_FILTER_TAG=productivity
#
# Usage:
#   source "$REPO_ROOT/os/lib/packages_list.sh"
#   packages_list_foreach "$list_file" my_callback
#   # my_callback receives: name version source kind tags

# shellcheck disable=SC2034
PACKAGES_LIST_FORMAT_VERSION=2

packages_list_valid_kind() {
  case "$1" in
    cli|tui|gui) return 0 ;;
    *) return 1 ;;
  esac
}

# Return 0 if kind/tags pass current PACKAGES_FILTER_* env filters.
packages_list_match_filters() {
  local kind="${1:-}" tags="${2:-}"
  local tag part

  if [[ -n "${PACKAGES_FILTER_KIND:-}" && "$kind" != "$PACKAGES_FILTER_KIND" ]]; then
    return 1
  fi

  if [[ -n "${PACKAGES_FILTER_TAG:-}" ]]; then
    tag="${PACKAGES_FILTER_TAG}"
    case ",${tags}," in
      *",${tag},"*) ;;
      *) return 1 ;;
    esac
  fi
  return 0
}

packages_list_foreach() {
  local list_file="$1"
  local callback="$2"
  local line line_no=0
  local name version source kind tags

  if [[ -z "$list_file" || -z "$callback" ]]; then
    echo "packages_list_foreach: usage: packages_list_foreach <file> <callback>" >&2
    return 2
  fi
  if [[ ! -f "$list_file" ]]; then
    echo "packages_list_foreach: file not found: $list_file" >&2
    return 1
  fi
  if ! declare -F "$callback" >/dev/null 2>&1; then
    echo "packages_list_foreach: callback not found: $callback" >&2
    return 2
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    # trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue

    # shellcheck disable=SC2086
    set -- $line
    if [[ $# -lt 5 ]]; then
      echo "packages_list_foreach: ${list_file}:${line_no}: expected 5 columns (name version source kind tags), got: $line" >&2
      return 1
    fi
    name="$1"
    version="$2"
    source="$3"
    kind="$4"
    tags="$5"
    if ! packages_list_valid_kind "$kind"; then
      echo "packages_list_foreach: ${list_file}:${line_no}: invalid kind '$kind' (use cli|tui|gui)" >&2
      return 1
    fi
    "$callback" "$name" "$version" "$source" "$kind" "$tags" || return $?
  done < "$list_file"
}

packages_list_print() {
  local list_file="$1"
  _packages_list_print_cb() {
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"
  }
  packages_list_foreach "$list_file" _packages_list_print_cb
}

packages_list_get_version() {
  local list_file="$1"
  local want_name="$2"
  local found=""

  _packages_list_get_version_cb() {
    local name="$1" version="$2"
    if [[ "$name" == "$want_name" ]]; then
      found="$version"
    fi
  }
  packages_list_foreach "$list_file" _packages_list_get_version_cb || return $?
  if [[ -z "$found" ]]; then
    echo "packages_list_get_version: package not found: $want_name in $list_file" >&2
    return 1
  fi
  printf '%s\n' "$found"
}

packages_list_has() {
  local list_file="$1"
  local want_name="$2"
  local found=0

  _packages_list_has_cb() {
    if [[ "$1" == "$want_name" ]]; then
      found=1
    fi
  }
  packages_list_foreach "$list_file" _packages_list_has_cb || return $?
  [[ "$found" -eq 1 ]]
}

# Resolve the CLI command used to detect presence for a package name.
packages_list_pkg_command() {
  case "$1" in
    rg|ripgrep) echo "rg" ;;
    git-delta) echo "delta" ;;
    visual-studio-code) echo "code" ;;
    neovim) echo "nvim" ;;
    oh-my-zsh|nerd-fonts) echo "" ;;
    *) echo "$1" ;;
  esac
}

# Homebrew formula name (list may use short CLI names like rg).
packages_list_brew_formula() {
  case "$1" in
    rg) echo "ripgrep" ;;
    *) echo "$1" ;;
  esac
}

# apt/dnf package name for list entries that use CLI short names.
packages_list_sys_pkg() {
  case "$1" in
    rg) echo "ripgrep" ;;
    *) echo "$1" ;;
  esac
}

# Lookup one entry. Prints: name<TAB>version<TAB>source<TAB>kind<TAB>tags
packages_list_lookup() {
  local list_file="$1"
  local want_name="$2"
  local found_line=""

  _packages_list_lookup_cb() {
    if [[ "$1" == "$want_name" ]]; then
      found_line="$(printf '%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5")"
    fi
  }
  packages_list_foreach "$list_file" _packages_list_lookup_cb || return $?
  if [[ -z "$found_line" ]]; then
    echo "packages_list_lookup: package not found: $want_name in $list_file" >&2
    return 1
  fi
  printf '%s\n' "$found_line"
}

# Default presence check via command -v (override with package_is_installed).
packages_list_default_is_installed() {
  local name="$1"
  local cmd
  cmd="$(packages_list_pkg_command "$name")"
  case "$name" in
    oh-my-zsh)
      [[ -d "${HOME}/.oh-my-zsh" ]]
      return $?
      ;;
    nerd-fonts)
      [[ -f /usr/share/fonts/nerd-fonts/.nerd-fonts-installed ]]
      return $?
      ;;
    bat)
      command -v bat &>/dev/null || command -v batcat &>/dev/null
      return $?
      ;;
  esac
  [[ -n "$cmd" ]] && command -v "$cmd" &>/dev/null
}

# Grow a column width to at least the display length of value.
packages_list_width() {
  local width="$1" value="$2"
  local n=${#value}
  if [[ "$n" -gt "$width" ]]; then
    printf '%s\n' "$n"
  else
    printf '%s\n' "$width"
  fi
}

packages_list_dashes() {
  printf '%*s' "$1" '' | tr ' ' '-'
}

# Print install status for every entry (honors PACKAGES_FILTER_KIND / PACKAGES_FILTER_TAG).
# If the caller defined package_is_installed(name, version, source), use it;
# otherwise fall back to packages_list_default_is_installed.
# Columns are sized from headers plus visible rows so STATUS stays aligned.
packages_list_check() {
  local list_file="$1"
  local installed=0 missing=0 skipped=0
  local name_w=4 version_w=7 source_w=6 kind_w=4 tags_w=4 status_w=6
  local rows="" fmt

  if [[ ! -f "$list_file" ]]; then
    echo "packages_list_check: file not found: $list_file" >&2
    return 1
  fi

  if [[ -n "${PACKAGES_FILTER_KIND:-}" || -n "${PACKAGES_FILTER_TAG:-}" ]]; then
    echo "filters: kind=${PACKAGES_FILTER_KIND:-*} tag=${PACKAGES_FILTER_TAG:-*}"
  fi

  _packages_list_check_cb() {
    local name="$1" version="$2" source="$3" kind="$4" tags="$5" status
    if ! packages_list_match_filters "$kind" "$tags"; then
      skipped=$((skipped + 1))
      return 0
    fi
    if declare -F package_is_installed >/dev/null 2>&1; then
      if package_is_installed "$name" "$version" "$source"; then
        status="installed"
        installed=$((installed + 1))
      else
        status="missing"
        missing=$((missing + 1))
      fi
    else
      if packages_list_default_is_installed "$name" "$version" "$source"; then
        status="installed"
        installed=$((installed + 1))
      else
        status="missing"
        missing=$((missing + 1))
      fi
    fi
    name_w="$(packages_list_width "$name_w" "$name")"
    version_w="$(packages_list_width "$version_w" "$version")"
    source_w="$(packages_list_width "$source_w" "$source")"
    kind_w="$(packages_list_width "$kind_w" "$kind")"
    tags_w="$(packages_list_width "$tags_w" "$tags")"
    status_w="$(packages_list_width "$status_w" "$status")"
    rows="${rows}${name}"$'\t'"${version}"$'\t'"${source}"$'\t'"${kind}"$'\t'"${tags}"$'\t'"${status}"$'\n'
  }

  packages_list_foreach "$list_file" _packages_list_check_cb || return $?

  fmt="%-${name_w}s %-${version_w}s %-${source_w}s %-${kind_w}s %-${tags_w}s %-${status_w}s\n"
  # shellcheck disable=SC2059
  printf "$fmt" "NAME" "VERSION" "SOURCE" "KIND" "TAGS" "STATUS"
  # shellcheck disable=SC2059
  printf "$fmt" \
    "$(packages_list_dashes "$name_w")" \
    "$(packages_list_dashes "$version_w")" \
    "$(packages_list_dashes "$source_w")" \
    "$(packages_list_dashes "$kind_w")" \
    "$(packages_list_dashes "$tags_w")" \
    "$(packages_list_dashes "$status_w")"

  if [[ -n "$rows" ]]; then
    while IFS=$'\t' read -r name version source kind tags status || [[ -n "${name:-}" ]]; do
      [[ -z "${name:-}" ]] && continue
      # shellcheck disable=SC2059
      printf "$fmt" "$name" "$version" "$source" "$kind" "$tags" "$status"
    done <<EOF
${rows}
EOF
  fi

  echo ""
  if [[ "$skipped" -gt 0 ]]; then
    echo "summary: ${installed} installed, ${missing} missing (${skipped} filtered out)"
  else
    echo "summary: ${installed} installed, ${missing} missing"
  fi
}
