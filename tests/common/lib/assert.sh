#!/usr/bin/env bash
# Shared assertions for module integration suites.
# shellcheck shell=bash

assert_eq() {
  local actual="$1" expected="$2" msg="${3:-values differ}"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $msg" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-missing substring}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: $msg" >&2
    echo "  expected to contain: $needle" >&2
    echo "  actual: $haystack" >&2
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-unexpected substring}"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "FAIL: $msg" >&2
    echo "  should not contain: $needle" >&2
    echo "  actual: $haystack" >&2
    return 1
  fi
}

assert_file_exists() {
  local path="$1" msg="${2:-file missing: $1}"
  if [[ ! -e "$path" ]]; then
    echo "FAIL: $msg" >&2
    return 1
  fi
}

assert_symlink() {
  local path="$1" msg="${2:-not a symlink: $1}"
  if [[ ! -L "$path" ]]; then
    echo "FAIL: $msg" >&2
    return 1
  fi
}

pass() {
  echo "PASS: $*"
}
