#!/usr/bin/env python3
"""
BC Ferries Unified CLI Tool
Combines monitoring, booking, and hybrid workflows

Usage:
    bc-ferries monitor --from "Departure Bay" --to "Horseshoe Bay" --date "10/15/2025" --time "1:20 pm"
    bc-ferries book (uses environment variables)
    bc-ferries monitor-and-book --from "Departure Bay" --to "Horseshoe Bay" --date "10/15/2025" --time "1:20 pm"

Version: 1.0.0
"""

import sys
import os
import argparse
import json
from datetime import datetime

VERSION = "1.0.0"


def cmd_monitor(args):
    """Monitor ferry availability using wait-for-ferry"""
    import subprocess

    cmd = ["wait-for-ferry"]
    cmd.extend(["--from", args.departure])
    cmd.extend(["--to", args.arrival])
    cmd.extend(["--date", args.date])
    cmd.extend(["--time", args.time])

    if args.adults:
        cmd.extend(["--adults", str(args.adults)])
    if args.children:
        cmd.extend(["--children", str(args.children)])
    if args.seniors:
        cmd.extend(["--seniors", str(args.seniors)])
    if args.infants:
        cmd.extend(["--infants", str(args.infants)])

    if args.vehicle:
        cmd.append("--vehicle")
    else:
        cmd.append("--no-vehicle")

    if args.poll_interval:
        cmd.extend(["--poll-interval", str(args.poll_interval)])
    if args.timeout:
        cmd.extend(["--timeout", str(args.timeout)])

    if args.verbose:
        cmd.append("--verbose")
    if args.json:
        cmd.append("--json")

    return subprocess.call(cmd)


def cmd_book(args):
    """Run booking automation using bc-ferries-book"""
    import subprocess

    # Booking uses environment variables - just call the tool
    return subprocess.call(["bc-ferries-book"])


def cmd_monitor_and_book(args):
    """Monitor for availability, then automatically book when available"""
    import subprocess

    print("🚢 BC Ferries Monitor & Auto-Book Workflow")
    print("=" * 70)
    print()

    # Step 1: Monitor for availability
    print("Step 1: Monitoring for ferry availability...")
    print("-" * 70)

    monitor_cmd = ["wait-for-ferry"]
    monitor_cmd.extend(["--from", args.departure])
    monitor_cmd.extend(["--to", args.arrival])
    monitor_cmd.extend(["--date", args.date])
    monitor_cmd.extend(["--time", args.time])

    if args.adults:
        monitor_cmd.extend(["--adults", str(args.adults)])
    if args.children:
        monitor_cmd.extend(["--children", str(args.children)])
    if args.seniors:
        monitor_cmd.extend(["--seniors", str(args.seniors)])
    if args.infants:
        monitor_cmd.extend(["--infants", str(args.infants)])

    if args.vehicle:
        monitor_cmd.append("--vehicle")
    else:
        monitor_cmd.append("--no-vehicle")

    if args.poll_interval:
        monitor_cmd.extend(["--poll-interval", str(args.poll_interval)])
    if args.timeout:
        monitor_cmd.extend(["--timeout", str(args.timeout)])

    monitor_cmd.append("--verbose")

    result = subprocess.call(monitor_cmd)

    if result != 0:
        print()
        print("❌ Monitoring failed or timed out - not proceeding to booking")
        return result

    print()
    print("✅ Ferry became available!")
    print()

    # Step 2: Book the ferry
    print("Step 2: Starting booking automation...")
    print("-" * 70)
    print()

    # Set environment variables from args if not already set
    if not os.environ.get("DEPARTURE"):
        os.environ["DEPARTURE"] = args.departure
    if not os.environ.get("ARRIVAL"):
        os.environ["ARRIVAL"] = args.arrival
    if not os.environ.get("DATE"):
        # Convert MM/DD/YYYY to YYYY-MM-DD
        try:
            date_obj = datetime.strptime(args.date, "%m/%d/%Y")
            os.environ["DATE"] = date_obj.strftime("%Y-%m-%d")
        except:
            os.environ["DATE"] = args.date
    if not os.environ.get("SAILING_TIME"):
        os.environ["SAILING_TIME"] = args.time
    if not os.environ.get("ADULTS"):
        os.environ["ADULTS"] = str(args.adults or 1)
    if args.children and not os.environ.get("CHILDREN"):
        os.environ["CHILDREN"] = str(args.children)
    if args.seniors and not os.environ.get("SENIORS"):
        os.environ["SENIORS"] = str(args.seniors)

    book_result = subprocess.call(["bc-ferries-book"])

    if book_result == 0:
        print()
        print("🎉 Booking completed successfully!")
    else:
        print()
        print("❌ Booking failed")

    return book_result


def main():
    parser = argparse.ArgumentParser(
        description="BC Ferries unified CLI - Monitor, book, or both",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Monitor until available
  bc-ferries monitor --from "Departure Bay" --to "Horseshoe Bay" \\
    --date "10/15/2025" --time "1:20 pm" --adults 2 --vehicle

  # Book a ferry (uses environment variables)
  export DEPARTURE="Departure Bay"
  export ARRIVAL="Horseshoe Bay"
  export DATE="2026-01-24"
  export SAILING_TIME="1:10 pm"
  export BC_FERRIES_EMAIL="user@example.com"
  export BC_FERRIES_PASSWORD="password"
  # ... (set payment details)
  bc-ferries book

  # Monitor AND auto-book when available (hybrid workflow)
  bc-ferries monitor-and-book --from "Departure Bay" --to "Horseshoe Bay" \\
    --date "10/15/2025" --time "1:20 pm" --adults 2 --vehicle

Commands:
  monitor           - Poll BC Ferries API until sailing becomes available
  book             - Run automated booking (requires env vars)
  monitor-and-book - Monitor for availability, then auto-book when found
        """
    )

    parser.add_argument("--version", "-v", action="version", version=f"bc-ferries {VERSION}")

    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # Monitor command
    monitor_parser = subparsers.add_parser("monitor", help="Monitor ferry availability")
    monitor_parser.add_argument("--from", dest="departure", required=True,
                                help="Departure terminal (e.g., 'Departure Bay')")
    monitor_parser.add_argument("--to", dest="arrival", required=True,
                                help="Arrival terminal (e.g., 'Horseshoe Bay')")
    monitor_parser.add_argument("--date", required=True,
                                help="Departure date in MM/DD/YYYY format")
    monitor_parser.add_argument("--time", required=True,
                                help="Departure time (e.g., '1:20 pm')")
    monitor_parser.add_argument("--adults", type=int, default=1)
    monitor_parser.add_argument("--children", type=int, default=0)
    monitor_parser.add_argument("--seniors", type=int, default=0)
    monitor_parser.add_argument("--infants", type=int, default=0)
    monitor_parser.add_argument("--vehicle", dest="vehicle", action="store_true", default=True)
    monitor_parser.add_argument("--no-vehicle", dest="vehicle", action="store_false")
    monitor_parser.add_argument("--poll-interval", type=int, default=10)
    monitor_parser.add_argument("--timeout", type=int, default=3600)
    monitor_parser.add_argument("-v", "--verbose", action="store_true")
    monitor_parser.add_argument("--json", action="store_true")

    # Book command
    book_parser = subparsers.add_parser("book", help="Run booking automation")

    # Monitor-and-book command (hybrid)
    hybrid_parser = subparsers.add_parser("monitor-and-book",
                                         help="Monitor then auto-book when available")
    hybrid_parser.add_argument("--from", dest="departure", required=True,
                              help="Departure terminal")
    hybrid_parser.add_argument("--to", dest="arrival", required=True,
                              help="Arrival terminal")
    hybrid_parser.add_argument("--date", required=True,
                              help="Departure date in MM/DD/YYYY format")
    hybrid_parser.add_argument("--time", required=True,
                              help="Departure time (e.g., '1:20 pm')")
    hybrid_parser.add_argument("--adults", type=int, default=1)
    hybrid_parser.add_argument("--children", type=int, default=0)
    hybrid_parser.add_argument("--seniors", type=int, default=0)
    hybrid_parser.add_argument("--infants", type=int, default=0)
    hybrid_parser.add_argument("--vehicle", dest="vehicle", action="store_true", default=True)
    hybrid_parser.add_argument("--no-vehicle", dest="vehicle", action="store_false")
    hybrid_parser.add_argument("--poll-interval", type=int, default=10)
    hybrid_parser.add_argument("--timeout", type=int, default=3600)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 2

    if args.command == "monitor":
        return cmd_monitor(args)
    elif args.command == "book":
        return cmd_book(args)
    elif args.command == "monitor-and-book":
        return cmd_monitor_and_book(args)
    else:
        print(f"Unknown command: {args.command}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
