# Xray Linux TUN Mode Design

## Goal

Add an opt-in `--tun` mode to `tools/vpn/client/linux_setup.sh` for Linux hosts while preserving the existing SOCKS/HTTP installation as the default. TUN mode must keep the existing China-direct/foreign-proxy Xray routing policy and must restore normal host routing when disabled or removed.

## Command Behaviour

- `linux_setup.sh install ...` keeps the current SOCKS5 and HTTP-only behaviour.
- `linux_setup.sh install --tun ...` additionally creates an `xray0` TUN inbound and installs host policy routing.
- SOCKS5 and HTTP inbounds remain available in TUN mode for compatibility with `setproxy` and applications that explicitly use a proxy.
- Reinstalling without `--tun` removes any previously managed TUN routing before starting the normal service.
- `status` reports the TUN interface, route helper state, and managed policy rules when TUN mode is installed.
- `clean` removes the TUN routing rules, helper, unit, Xray configuration, and Xray client unit.

## Traffic Model

The existing Xray routing rules remain authoritative after packets enter `xray0`: private and Chinese destinations use the `direct` outbound, while foreign destinations use the VLESS Reality `proxy` outbound.

Linux policy routing uses a dedicated table containing default IPv4 and IPv6 routes through `xray0`. A `uidrange` rule applies that table only to locally originated host traffic, so forwarded traffic from containers, virtual machines, and routers is not captured. Both Xray outbounds set a Linux socket mark, and a higher-priority `fwmark` rule sends marked Xray sockets through the normal main table. This prevents Xray outbound connections from re-entering the TUN interface.

The route helper performs idempotent `up` and `down` operations. The systemd TUN routing unit starts after `xray-client.service`, is wanted by the Xray client only in TUN mode, and is bound to the Xray service lifecycle. Stopping or reinstalling the client removes the managed rules. If the TUN route table becomes empty unexpectedly, Linux policy lookup falls through to the main table, favouring restored direct connectivity over a host-wide outage.

## Compatibility and Limitations

- TUN mode is Linux-only and opt-in; macOS configuration is unchanged.
- Xray v26.3.27 is retained. Its TUN implementation supports TCP and UDP but not ICMP, so `ping` is not a TUN connectivity test.
- Existing terminal proxy commands remain valid but are normally unnecessary in TUN mode.
- No `GIT_SSH_COMMAND` is introduced by TUN mode.
- Host TCP/UDP traffic is captured; forwarded container and virtual-machine traffic is intentionally excluded.
- Domain sniffing is enabled on the TUN inbound for HTTP, TLS, and QUIC. Traffic without a recoverable domain falls back to the existing GeoIP routing rules.

## Files

- `tools/vpn/client/linux_setup.sh`: parse `--tun`, render the TUN-aware Xray and systemd configurations, install/remove routing support, and report status.
- `tools/vpn/client/bin/xray-tun-route`: idempotent Linux policy-route helper with `up`, `down`, and `status` actions.
- `tools/vpn/client/linux_setup_test.sh`: isolated shell regression coverage using temporary output directories and a fake `ip` command.
- `tools/vpn/README.md`: Linux TUN installation, behaviour, limitations, and rollback documentation.

## Verification

Regression tests must prove that the default configuration contains no TUN inbound or socket marks, `--tun` produces the TUN inbound and marked outbounds, the generated systemd units have the required lifecycle relationship, and route helper actions issue only the owned policy route operations. Syntax checks, the Linux setup regression suite, and the existing setproxy regression suite must all pass.
