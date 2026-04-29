#!/usr/bin/env python3
"""
Compute the complement of China IP CIDR ranges.

Input:  China CIDR list (one per line, from update_cn_ips.sh)
Output: AllowedIPs list for WireGuard clients — covers the entire IPv4
        space EXCEPT the China IP ranges, so only overseas traffic
        enters the tunnel while domestic traffic bypasses it.

Algorithm: O(n log n) integer-range merge, much faster than the naive
           O(n²) address_exclude approach for large CIDR lists.

Usage:
    python3 cn_cidr_complement.py --cn-file cn_cidrs.txt
    python3 cn_cidr_complement.py --cn-file cn_cidrs.txt --include-private
    python3 cn_cidr_complement.py < cn_cidrs.txt
"""

from __future__ import annotations  # enables list[X] syntax on Python 3.6/3.7

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
    """Return all IPv4 space minus the excluded CIDRs.

    Uses an O(n log n) integer-range algorithm instead of the naive
    O(n²) address_exclude approach, making it fast even for 8000+ CIDRs.
    """

    # Private / special ranges that are useful to keep local
    private_ranges = [
        ipaddress.IPv4Network("0.0.0.0/8"),
        ipaddress.IPv4Network("10.0.0.0/8"),
        ipaddress.IPv4Network("100.64.0.0/10"),
        ipaddress.IPv4Network("127.0.0.0/8"),
        ipaddress.IPv4Network("169.254.0.0/16"),
        ipaddress.IPv4Network("172.16.0.0/12"),
        ipaddress.IPv4Network("192.168.0.0/16"),
        ipaddress.IPv4Network("192.0.0.0/24"),
        ipaddress.IPv4Network("198.18.0.0/15"),
        ipaddress.IPv4Network("198.51.100.0/24"),
        ipaddress.IPv4Network("203.0.113.0/24"),
        ipaddress.IPv4Network("224.0.0.0/4"),
        ipaddress.IPv4Network("240.0.0.0/4"),
        ipaddress.IPv4Network("255.255.255.255/32"),
    ]

    to_exclude = list(exclude)
    if not include_private:
        to_exclude.extend(private_ranges)

    # Convert each network to an integer (start, end) range
    ranges: list[tuple[int, int]] = [
        (int(n.network_address), int(n.broadcast_address))
        for n in to_exclude
    ]
    ranges.sort()

    # Merge overlapping / adjacent ranges — O(n log n)
    merged: list[list[int]] = []
    for start, end in ranges:
        if merged and start <= merged[-1][1] + 1:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])

    # Walk the gaps between merged ranges to build the complement
    IPV4_MAX = (1 << 32) - 1
    result: list[ipaddress.IPv4Network] = []
    prev_end = -1

    for start, end in merged:
        if start > prev_end + 1:
            result.extend(
                ipaddress.summarize_address_range(
                    ipaddress.IPv4Address(prev_end + 1),
                    ipaddress.IPv4Address(start - 1),
                )
            )
        prev_end = max(prev_end, end)

    if prev_end < IPV4_MAX:
        result.extend(
            ipaddress.summarize_address_range(
                ipaddress.IPv4Address(prev_end + 1),
                ipaddress.IPv4Address(IPV4_MAX),
            )
        )

    return result


def main():
    parser = argparse.ArgumentParser(
        description="Compute non-China AllowedIPs for WireGuard split tunneling"
    )
    parser.add_argument(
        "--cn-file", "-f",
        help="File containing China CIDRs (one per line). Reads stdin if omitted.",
    )
    parser.add_argument(
        "--exclude", "-e",
        action="append",
        default=[],
        metavar="IP/CIDR",
        help="Additional IPs/CIDRs to exclude from AllowedIPs (e.g. VPN server endpoint). "
             "Can be specified multiple times.",
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

    if args.cn_file:
        with open(args.cn_file) as f:
            lines = f.readlines()
    else:
        if sys.stdin.isatty():
            print("Reading China CIDRs from stdin (Ctrl+D to finish)...", file=sys.stderr)
        lines = sys.stdin.readlines()

    cn_cidrs = parse_cidrs(lines)

    # Parse additional exclusions (e.g. VPN server endpoint IP)
    extra_excludes = []
    for item in args.exclude:
        try:
            # Accept bare IPs like "1.2.3.4" as /32
            if '/' not in item:
                item = item + '/32'
            extra_excludes.append(ipaddress.IPv4Network(item, strict=False))
        except ValueError as e:
            print(f"[warn] skipping invalid --exclude '{item}': {e}", file=sys.stderr)

    if args.stats:
        print(f"[stats] China CIDR blocks: {len(cn_cidrs)}", file=sys.stderr)
        if extra_excludes:
            print(f"[stats] Extra exclusions: {[str(x) for x in extra_excludes]}", file=sys.stderr)

    all_excludes = cn_cidrs + extra_excludes
    complement = cidr_complement(all_excludes, include_private=args.include_private)
    if args.stats:
        print(f"[stats] AllowedIPs CIDR blocks: {len(complement)}", file=sys.stderr)

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
