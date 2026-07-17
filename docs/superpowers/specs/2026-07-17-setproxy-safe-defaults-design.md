# Setproxy Safe Defaults Design

## Goal

Make `setproxy` enable only terminal HTTP/SOCKS proxy variables by default. Git SSH, Docker daemon proxy, and the Linux dnf system proxy become explicit, safe-to-restore integrations.

## Command Behaviour

- `setproxy on` writes shell HTTP/HTTPS/SOCKS variables and, on Linux systems with `dnf`, writes the dnf HTTP proxy.
- Git SSH proxying is disabled by default. `setproxy on --git-ssh` (or `VPN_GIT_SSH_PROXY=true`) exports `GIT_SSH_COMMAND`; `--no-git-ssh` explicitly disables it.
- Docker daemon changes are disabled by default. `setproxy on --docker-daemon` is required before a Linux Docker daemon or Colima configuration is changed.
- `setproxy off` restores any dnf or Docker configuration previously managed by `setproxy`, even if the caller does not repeat `--docker-daemon`.

## dnf Integration

On Linux, only when `dnf` is available, `setproxy on` uses `sudo` to set `proxy=http://<HTTP_HOST>:<HTTP_PORT>` in `/etc/dnf/dnf.conf` (with an environment override for tests). Before changing it, the command records the pre-existing proxy setting and the value it writes in a private state file under `~/.config/vpn`.

`setproxy off` restores the original proxy state only if the current dnf configuration still matches the value written by `setproxy`. If another tool or user changed it, `setproxy` leaves that value intact and warns instead of overwriting it. macOS and Linux hosts without dnf do not receive dnf changes.

## Docker Integration

The existing state file and merge/restore logic remains the authority for Docker daemon proxy changes. The only behaviour change is gating `configure_docker_proxy_on` behind `--docker-daemon`; existing state is still restored by `setproxy off` to avoid leaving an active daemon proxy behind.

## Testing

Extend `tools/vpn/client/setproxy_test.sh` to prove:

- a default `on --emit` unsets rather than exports `GIT_SSH_COMMAND`;
- `--git-ssh` still exports it, and `--no-git-ssh` wins when chosen;
- Docker is unchanged without `--docker-daemon` and is configured with it;
- dnf receives the selected HTTP proxy, restores a previous proxy, and does not overwrite an externally changed proxy during `off`.

The test harness will provide a fake `sudo` and an overridable dnf configuration path, so it does not touch the host's `/etc/dnf/dnf.conf`.
