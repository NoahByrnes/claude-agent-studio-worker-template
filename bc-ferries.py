#!/usr/bin/env python3
"""
BC Ferries Unified CLI Tool with Background Daemon Support
Combines monitoring, booking, and hybrid workflows

Usage:
    # Launch background daemon (non-blocking, returns immediately)
    bc-ferries monitor-and-book --daemon \\
      --from "Departure Bay" --to "Horseshoe Bay" \\
      --date "10/15/2025" --time "1:20 pm"

    # Check daemon status
    bc-ferries status

    # View daemon logs
    bc-ferries logs

    # Stop daemon
    bc-ferries stop

    # Foreground mode (blocks)
    bc-ferries monitor-and-book \\
      --from "Departure Bay" --to "Horseshoe Bay" \\
      --date "10/15/2025" --time "1:20 pm"

Version: 2.0.0
"""

import sys
import os
import argparse
import json
import signal
import subprocess
import time
from datetime import datetime
from pathlib import Path

VERSION = "2.0.0"

# Daemon state files
PID_FILE = "/tmp/bc-ferries.pid"
LOG_FILE = "/tmp/bc-ferries.log"
STATE_FILE = "/tmp/bc-ferries-state.json"
RESULT_FILE = "/tmp/ferry-booking-result.json"


def write_state(state: dict):
    """Write daemon state to state file"""
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)


def read_state() -> dict:
    """Read daemon state from state file"""
    if not os.path.exists(STATE_FILE):
        return {}
    try:
        with open(STATE_FILE, 'r') as f:
            return json.load(f)
    except:
        return {}


def is_daemon_running() -> bool:
    """Check if daemon is currently running"""
    if not os.path.exists(PID_FILE):
        return False

    try:
        with open(PID_FILE, 'r') as f:
            pid = int(f.read().strip())

        # Check if process exists
        os.kill(pid, 0)
        return True
    except (OSError, ValueError, ProcessLookupError):
        # Process doesn't exist, clean up stale PID file
        try:
            os.remove(PID_FILE)
        except:
            pass
        return False


def get_daemon_pid() -> int:
    """Get daemon PID if running"""
    if not os.path.exists(PID_FILE):
        return None

    try:
        with open(PID_FILE, 'r') as f:
            return int(f.read().strip())
    except:
        return None


def daemon_monitor_and_book(args):
    """
    Daemon process that monitors and books.
    This function runs in background.
    """
    # Write PID file
    with open(PID_FILE, 'w') as f:
        f.write(str(os.getpid()))

    # Redirect stdout/stderr to log file
    log_file = open(LOG_FILE, 'w')
    sys.stdout = log_file
    sys.stderr = log_file

    # Write initial state
    state = {
        "status": "monitoring",
        "started_at": datetime.now().isoformat(),
        "departure": args.departure,
        "arrival": args.arrival,
        "date": args.date,
        "time": args.time,
        "pid": os.getpid()
    }
    write_state(state)

    print(f"🚢 BC Ferries Daemon Started (PID: {os.getpid()})")
    print(f"Monitoring: {args.departure} → {args.arrival}")
    print(f"Date: {args.date}, Time: {args.time}")
    print("=" * 70)
    print()

    try:
        # Step 1: Monitor for availability
        print("Step 1: Monitoring for ferry availability...")
        print("-" * 70)

        state["status"] = "monitoring"
        write_state(state)

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
            print("❌ Monitoring failed or timed out")
            state["status"] = "failed"
            state["error"] = "Monitoring failed or timed out"
            state["completed_at"] = datetime.now().isoformat()
            write_state(state)

            # Write result file
            with open(RESULT_FILE, 'w') as f:
                json.dump({
                    "success": False,
                    "stage": "monitoring",
                    "error": "Monitoring failed or timed out",
                    "timestamp": datetime.now().isoformat()
                }, f, indent=2)

            return 1

        print()
        print("✅ Ferry became available!")
        print()

        # Step 2: Book the ferry
        print("Step 2: Starting booking automation...")
        print("-" * 70)

        state["status"] = "booking"
        state["available_at"] = datetime.now().isoformat()
        write_state(state)

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
            state["status"] = "completed"
            state["completed_at"] = datetime.now().isoformat()
            write_state(state)

            # Write success result
            with open(RESULT_FILE, 'w') as f:
                json.dump({
                    "success": True,
                    "stage": "booking",
                    "departure": args.departure,
                    "arrival": args.arrival,
                    "date": args.date,
                    "time": args.time,
                    "completed_at": datetime.now().isoformat()
                }, f, indent=2)
        else:
            print()
            print("❌ Booking failed")
            state["status"] = "failed"
            state["error"] = "Booking automation failed"
            state["completed_at"] = datetime.now().isoformat()
            write_state(state)

            # Write failure result
            with open(RESULT_FILE, 'w') as f:
                json.dump({
                    "success": False,
                    "stage": "booking",
                    "error": "Booking automation failed",
                    "timestamp": datetime.now().isoformat()
                }, f, indent=2)

            return 1

        return 0

    except Exception as e:
        print(f"❌ Daemon error: {e}")
        state["status"] = "failed"
        state["error"] = str(e)
        state["completed_at"] = datetime.now().isoformat()
        write_state(state)

        # Write error result
        with open(RESULT_FILE, 'w') as f:
            json.dump({
                "success": False,
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }, f, indent=2)

        return 1

    finally:
        # Clean up PID file
        try:
            os.remove(PID_FILE)
        except:
            pass
        log_file.close()


def cmd_monitor(args):
    """Monitor ferry availability using wait-for-ferry"""
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
    return subprocess.call(["bc-ferries-book"])


def cmd_monitor_and_book(args):
    """Monitor for availability, then automatically book when available"""

    if args.daemon:
        # Launch as background daemon
        if is_daemon_running():
            print("❌ Daemon already running!")
            print(f"PID: {get_daemon_pid()}")
            print("Use 'bc-ferries status' to check state")
            print("Use 'bc-ferries stop' to stop it first")
            return 1

        print("🚀 Launching BC Ferries daemon in background...")
        print()
        print(f"Route: {args.departure} → {args.arrival}")
        print(f"Date: {args.date}, Time: {args.time}")
        print()

        # Fork process
        pid = os.fork()

        if pid > 0:
            # Parent process
            time.sleep(0.5)  # Give child time to start

            if is_daemon_running():
                print(f"✅ Daemon started successfully (PID: {pid})")
                print()
                print("Commands:")
                print("  bc-ferries status  - Check daemon status")
                print("  bc-ferries logs    - View daemon logs")
                print("  bc-ferries stop    - Stop daemon")
                print()
                print(f"Results will be written to: {RESULT_FILE}")
                return 0
            else:
                print("❌ Failed to start daemon")
                return 1
        else:
            # Child process - become daemon
            os.setsid()  # Create new session

            # Fork again to prevent zombie
            pid2 = os.fork()
            if pid2 > 0:
                sys.exit(0)

            # Run daemon
            return daemon_monitor_and_book(args)
    else:
        # Foreground mode (blocking)
        print("🚢 BC Ferries Monitor & Auto-Book Workflow (Foreground)")
        print("=" * 70)
        print()

        return daemon_monitor_and_book(args)


def cmd_status(args):
    """Check daemon status"""

    if not is_daemon_running():
        print("❌ No daemon running")

        # Check if there's a result file
        if os.path.exists(RESULT_FILE):
            print()
            print("Last run result:")
            with open(RESULT_FILE, 'r') as f:
                result = json.load(f)
            print(json.dumps(result, indent=2))

        return 1

    pid = get_daemon_pid()
    state = read_state()

    print("✅ Daemon is running")
    print()
    print(f"PID: {pid}")
    print(f"Status: {state.get('status', 'unknown')}")

    if state.get('status') == 'monitoring':
        print("📡 Currently monitoring for ferry availability...")
    elif state.get('status') == 'booking':
        print("🎫 Ferry became available - booking in progress...")
    elif state.get('status') == 'completed':
        print("🎉 Booking completed successfully!")
    elif state.get('status') == 'failed':
        print(f"❌ Failed: {state.get('error', 'Unknown error')}")

    print()
    print(f"Route: {state.get('departure')} → {state.get('arrival')}")
    print(f"Date: {state.get('date')}, Time: {state.get('time')}")
    print(f"Started: {state.get('started_at', 'unknown')}")

    if state.get('available_at'):
        print(f"Available: {state.get('available_at')}")

    if state.get('completed_at'):
        print(f"Completed: {state.get('completed_at')}")

    print()
    print("Commands:")
    print("  bc-ferries logs  - View daemon logs")
    print("  bc-ferries stop  - Stop daemon")

    return 0


def cmd_logs(args):
    """Show daemon logs"""

    if not os.path.exists(LOG_FILE):
        print("❌ No log file found")
        print(f"Expected: {LOG_FILE}")
        return 1

    if args.follow:
        # Follow mode (like tail -f)
        subprocess.call(["tail", "-f", LOG_FILE])
    else:
        # Show last N lines
        lines = args.lines or 50
        subprocess.call(["tail", "-n", str(lines), LOG_FILE])

    return 0


def cmd_stop(args):
    """Stop daemon"""

    if not is_daemon_running():
        print("❌ No daemon running")
        return 1

    pid = get_daemon_pid()

    try:
        print(f"🛑 Stopping daemon (PID: {pid})...")
        os.kill(pid, signal.SIGTERM)

        # Wait for process to exit
        for _ in range(10):
            time.sleep(0.5)
            if not is_daemon_running():
                break

        if is_daemon_running():
            print("⚠️  Daemon didn't stop gracefully, force killing...")
            os.kill(pid, signal.SIGKILL)
            time.sleep(0.5)

        if not is_daemon_running():
            print("✅ Daemon stopped")

            # Update state
            state = read_state()
            state["status"] = "stopped"
            state["stopped_at"] = datetime.now().isoformat()
            write_state(state)

            return 0
        else:
            print("❌ Failed to stop daemon")
            return 1

    except Exception as e:
        print(f"❌ Error stopping daemon: {e}")
        return 1


def main():
    parser = argparse.ArgumentParser(
        description="BC Ferries unified CLI with background daemon support",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:

  # Launch background daemon (non-blocking, returns immediately)
  bc-ferries monitor-and-book --daemon \\
    --from "Departure Bay" --to "Horseshoe Bay" \\
    --date "10/15/2025" --time "1:20 pm" \\
    --adults 2 --vehicle

  # Check daemon status
  bc-ferries status

  # View daemon logs (last 50 lines)
  bc-ferries logs

  # Follow logs in real-time
  bc-ferries logs --follow

  # Stop daemon
  bc-ferries stop

  # Foreground mode (blocks until complete)
  bc-ferries monitor-and-book \\
    --from "Departure Bay" --to "Horseshoe Bay" \\
    --date "10/15/2025" --time "1:20 pm"

Commands:
  monitor           - Poll BC Ferries API until sailing becomes available
  book             - Run automated booking (requires env vars)
  monitor-and-book - Monitor then auto-book (--daemon for background)
  status           - Check daemon status
  logs             - View daemon logs
  stop             - Stop background daemon
        """
    )

    parser.add_argument("--version", "-v", action="version", version=f"bc-ferries {VERSION}")

    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # Monitor command
    monitor_parser = subparsers.add_parser("monitor", help="Monitor ferry availability")
    monitor_parser.add_argument("--from", dest="departure", required=True)
    monitor_parser.add_argument("--to", dest="arrival", required=True)
    monitor_parser.add_argument("--date", required=True)
    monitor_parser.add_argument("--time", required=True)
    monitor_parser.add_argument("--adults", type=int, default=1)
    monitor_parser.add_argument("--children", type=int, default=0)
    monitor_parser.add_argument("--seniors", type=int, default=0)
    monitor_parser.add_argument("--infants", type=int, default=0)
    monitor_parser.add_argument("--vehicle", dest="vehicle", action="store_true", default=True)
    monitor_parser.add_argument("--no-vehicle", dest="vehicle", action="store_false")
    monitor_parser.add_argument("--poll-interval", type=int, default=10)
    monitor_parser.add_argument("--timeout", type=int, default=3600)
    monitor_parser.add_argument("--verbose", action="store_true")
    monitor_parser.add_argument("--json", action="store_true")

    # Book command
    book_parser = subparsers.add_parser("book", help="Run booking automation")

    # Monitor-and-book command
    hybrid_parser = subparsers.add_parser("monitor-and-book",
                                         help="Monitor then auto-book")
    hybrid_parser.add_argument("--daemon", action="store_true",
                              help="Run as background daemon (non-blocking)")
    hybrid_parser.add_argument("--from", dest="departure", required=True)
    hybrid_parser.add_argument("--to", dest="arrival", required=True)
    hybrid_parser.add_argument("--date", required=True)
    hybrid_parser.add_argument("--time", required=True)
    hybrid_parser.add_argument("--adults", type=int, default=1)
    hybrid_parser.add_argument("--children", type=int, default=0)
    hybrid_parser.add_argument("--seniors", type=int, default=0)
    hybrid_parser.add_argument("--infants", type=int, default=0)
    hybrid_parser.add_argument("--vehicle", dest="vehicle", action="store_true", default=True)
    hybrid_parser.add_argument("--no-vehicle", dest="vehicle", action="store_false")
    hybrid_parser.add_argument("--poll-interval", type=int, default=10)
    hybrid_parser.add_argument("--timeout", type=int, default=3600)

    # Status command
    status_parser = subparsers.add_parser("status", help="Check daemon status")

    # Logs command
    logs_parser = subparsers.add_parser("logs", help="View daemon logs")
    logs_parser.add_argument("-f", "--follow", action="store_true",
                            help="Follow log output (like tail -f)")
    logs_parser.add_argument("-n", "--lines", type=int,
                            help="Number of lines to show (default: 50)")

    # Stop command
    stop_parser = subparsers.add_parser("stop", help="Stop daemon")

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
    elif args.command == "status":
        return cmd_status(args)
    elif args.command == "logs":
        return cmd_logs(args)
    elif args.command == "stop":
        return cmd_stop(args)
    else:
        print(f"Unknown command: {args.command}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
