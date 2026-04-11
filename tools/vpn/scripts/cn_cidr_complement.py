#!/usr/bin/env python3
"""
Compute the complement of China IP CIDR ranges.

Input:  China CIDR list (one per line, from update_cn_ips.sh)
Output: AllowedIPs list for WireGuard clients — covers the entire IPv4
        space EXCEPT the China IP ranges, so only overseas traffic
        enters the tunnel while domestic traffic bypasses it.

Usage:
    python3 cn_cidr_complement.py --cn-file cn_cidrs.txt
    python3 cn_cidr_complement.py --cn-file cn_cidrs.txt --include-private
    python3 cn_cidr_complement.py < cn_cidrs.txt
"""

import sys
import ipaddress
import argparse


def parse_cidrs(lines: list[str]) -> list[ipaddress.IPv4Network]:
    nets = []
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        try:
            nets.append(ipaddress.IPv4Network(line, strict=False))
        except ValueError as e:
            print(f"[warn] skipping invalid CIDR '{line}': {e}", file=sys.stderr)
    return nets


def cidr_complement(
    exclude: list[ipaddress.IPv4Network],
    include_private: bool = False,
) -> list[ipaddress.IPv4Network]:
    """Return all IPv4 space minus the excluded CIDRs."""

    # Private / special ranges that are useful to keep local
    # (RFC1918, link-local, loopback, etc.)
    private_ranges = [
        ipaddress.IPv4Network("0.0.0.0/8"),        # "This" network
        ipaddress.IPv4Network("10.0.0.0/8"),        # RFC1918
        ipaddress.IPv4Network("100.64.0.0/10"),     # Shared address
        ipaddress.IPv4Network("127.0.0.0/8"),       # Loopback
        ipaddress.IPv4Network("169.254.0.0/16"),    # Link-local
        ipaddress.IPv4Network("172.16.0.0/12"),     # RFC1918
        ipaddress.IPv4Network("192.168.0.0/16"),    # RFC1918
        ipaddress.IPv4Network("192.0.0.0/24"),      # IETF protocol
        ipaddress.IPv4Network("198.18.0.0/15"),     # Benchmarking
        ipaddress.IPv4Network("198.51.100.0/24"),   # TEST-NET-2
        ipaddress.IPv4Network("203.0.113.0/24"),    # TEST-NET-3
        ipaddress.IPv4Network("224.0.0.0/4"),       # Multicast
        ipaddress.IPv4Network("240.0.0.0/4"),       # Reserved
        ipaddress.IPv4Network("255.255.255.255/32"),# Broadcast
    ]

    # Build the exclusion set: China IPs + (optionally) private ranges
    to_exclude = list(exclude)
    if not include_private:
        to_exclude.extend(private_ranges)

    # Collapse overlapping/adjacent networks for efficiency
    collapsed_exclude = list(ipaddress.collapse_addresses(to_exclude))

    # Start with entire IPv4 address space and subtract excluded ranges
    remaining = [ipaddress.IPv4Network("0.0.0.0/0")]
    for exc in collapsed_exclude:
        new_remaining = []
        for net in remaining:
            if net.overlaps(exc):
                new_remaining.extend(net.address_exclude(exc))
            else:
                new_remaining.append(net)
        remaining = new_remaining

    return sorted(remaining)


def main():
    parser = argparse.ArgumentParser(
        description="Compute non-China AllowedIPs for WireGuard split tunneling"
    )
    parser.add_argument(
        "--cn-file", "-f",
        help="File containing China CIDRs (one per line). Reads stdin if omitted.",
    )
    parser.add_argument(
        "--include-private",
        action="store_true",
        default=False,
        help="Also route private/RFC1918 ranges through tunnel (not recommended)",
    )
    parser.add_argument(
        "--output", "-o",
        help="Write result to file instead of stdout",
    )
    parser.add_argument(
        "--wg-format",
        action="store_true",
        default=False,
        help="Output as a single comma-separated line (WireGuard AllowedIPs format)",
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        default=False,
        help="Print statistics to stderr",
    )
    args = parser.parse_args()

    # Read input
    if args.cn_file:
        with open(args.cn_file) as f:
            lines = f.readlines()
    else:
        if sys.stdin.isatty():
            print("Reading China CIDRs from stdin (Ctrl+D to finish)...", file=sys.stderr)
        lines = sys.stdin.readlines()

    cn_cidrs = parse_cidrs(lines)
    if args.stats:
        print(f"[stats] China CIDR blocks: {len(cn_cidrs)}", file=sys.stderr)

    complement = cidr_complement(cn_cidrs, include_private=args.include_private)
    if args.stats:
        print(f"[stats] AllowedIPs CIDR blocks: {len(complement)}", file=sys.stderr)

    # Format output
    if args.wg_format:
        result = ", ".join(str(n) for n in complement)
    else:
        result = "\n".join(str(n) for n in complement)

    if args.output:
        with open(args.output, "w") as f:
            f.write(result)
            if not args.wg_format:
                f.write("\n")
        print(f"[ok] Written to {args.output}", file=sys.stderr)
    else:
        print(result)


if __name__ == "__main__":
    main()
