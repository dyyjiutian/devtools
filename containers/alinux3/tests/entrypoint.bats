#!/usr/bin/env bats

ROOT_DIR="${BATS_TEST_DIRNAME}/../../.."
ENTRYPOINT="${ROOT_DIR}/containers/alinux3/entrypoint.sh"
USER_SYNC="${ROOT_DIR}/containers/alinux3/user-sync.sh"

@test "entrypoint and user sync pass bash syntax checks" {
  run bash -n "$ENTRYPOINT"
  [ "$status" -eq 0 ]

  run bash -n "$USER_SYNC"
  [ "$status" -eq 0 ]
}

@test "entrypoint exposes help without requiring a container user" {
  run "$ENTRYPOINT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEV_UID"* ]]
}

@test "entrypoint rejects runtime user synchronization when not root" {
  run env DEV_UID=1001 DEV_GID=1001 "$ENTRYPOINT" id
  [ "$status" -ne 0 ]
  [[ "$output" == *"root"* || "$stderr" == *"root"* ]]
}
