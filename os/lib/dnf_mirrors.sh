#!/usr/bin/env bash
# Official DNF repo helpers: keep upstream files and add Aliyun companions
# when a known public mirror exists (currently Docker CE).
# Aliyun does not host GitHub CLI or NodeSource RPM repos.

set -euo pipefail

DNF_MIRRORS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DNF_MIRRORS_EPEL8_REPO="${DNF_MIRRORS_EPEL8_REPO:-${DNF_MIRRORS_LIB_DIR}/repos/epel-8-aliyun.repo}"
DNF_MIRRORS_ALIYUN_BASE="${DNF_MIRRORS_ALIYUN_BASE:-https://mirrors.aliyun.com}"

dnf_mirrors_aliyun_base() {
  printf '%s\n' "$DNF_MIRRORS_ALIYUN_BASE"
}

# Print the Aliyun URL on stdout. Return 1 when no known mapping exists.
dnf_mirrors_rewrite_url() {
  local url="$1"
  local prefix="https://download.docker.com/linux/centos"
  local alt="http://download.docker.com/linux/centos"
  local dest
  dest="$(dnf_mirrors_aliyun_base)/docker-ce/linux/centos"

  case "$url" in
    "${prefix}"|"${prefix}"/*)
      printf '%s\n' "${dest}${url#"$prefix"}"
      ;;
    "${alt}"|"${alt}"/*)
      printf '%s\n' "${dest}${url#"$alt"}"
      ;;
    *)
      return 1
      ;;
  esac
}

dnf_mirrors_section_aliyun_id() {
  local line="$1"
  local name
  name="${line#\[}"
  name="${name%\]}"
  case "$name" in
    *-aliyun) printf '%s\n' "$line" ;;
    *) printf '[%s-aliyun]\n' "$name" ;;
  esac
}

# Write an Aliyun companion repo. Return 1 if no URL could be rewritten.
dnf_mirrors_render_companion_repo() {
  local infile="$1" outfile="$2"
  local line key value rewritten=0 out="" mapped

  [[ -f "$infile" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      \[*\])
        out="${out}$(dnf_mirrors_section_aliyun_id "$line")"$'\n'
        ;;
      baseurl=*|gpgkey=*)
        key="${line%%=*}"
        value="${line#*=}"
        if mapped="$(dnf_mirrors_rewrite_url "$value")"; then
          out="${out}${key}=${mapped}"$'\n'
          rewritten=1
        else
          out="${out}${line}"$'\n'
        fi
        ;;
      *)
        out="${out}${line}"$'\n'
        ;;
    esac
  done <"$infile"

  [[ "$rewritten" -eq 1 ]] || return 1
  printf '%s' "$out" >"$outfile"
}

dnf_mirrors_write_epel_el8() {
  local dest="$1"
  [[ -f "$DNF_MIRRORS_EPEL8_REPO" ]] || return 1
  cp "$DNF_MIRRORS_EPEL8_REPO" "$dest"
}
