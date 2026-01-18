#!/usr/bin/env python3
"""
BC Ferries Availability Polling Tool

Polls the BC Ferries API until a specific sailing becomes available.
Returns when availability is found or timeout is reached.
"""

import sys
import time
import argparse
import json
from datetime import datetime
from typing import Optional, Dict

# BC Ferries API Client (embedded to avoid external dependencies)
import requests
from datetime import timedelta


class BCFerriesAPI:
    """Direct API client for BC Ferries"""

    BASE_URL = "https://apigateway.bcferries.com"
    CLIENT_ID = "4VfoEABTGssO0HTFqK9IrLlpFAoa"
    CLIENT_SECRET = "_z9OpdZO3XnvqfqIbHkfafa7JGAa"
    DEVICE_SCOPE = "device_5017EE34-7864-4B44-B6FB-E8C7CD311423"
    HYBRIS_AUTH = "Bearer 5TmceVnir39XSt-d0ulQd5UG3ys"

    TERMINALS = {
        "departure_bay": "NAN", "horseshoe_bay": "HSB",
        "tsawwassen": "TSA", "swartz_bay": "SWB",
        "duke_point": "DUK", "nanaimo": "NAN",
        "vancouver": "HSB", "victoria": "SWB"
    }

    def __init__(self):
        self.access_token = None
        self.token_expiry = None

    def get_access_token(self, force_refresh: bool = False) -> str:
        """Get OAuth access token (cached for 1 hour)"""
        if not force_refresh and self.access_token and self.token_expiry:
            if datetime.now() < self.token_expiry:
                return self.access_token

        response = requests.post(
            f"{self.BASE_URL}/token",
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            data={
                "grant_type": "client_credentials",
                "scope": self.DEVICE_SCOPE,
                "client_id": self.CLIENT_ID,
                "client_secret": self.CLIENT_SECRET
            }
        )

        if response.status_code != 200:
            raise Exception(f"Failed to get access token: {response.status_code}")

        data = response.json()
        self.access_token = data["access_token"]
        expires_in = data.get("expires_in", 3600)
        self.token_expiry = datetime.now() + timedelta(seconds=expires_in - 300)
        return self.access_token

    def _make_request(self, method: str, endpoint: str, **kwargs) -> Dict:
        """Make authenticated API request"""
        token = self.get_access_token()
        headers = kwargs.pop("headers", {})
        headers.update({
            "Authorization": f"Bearer {token}",
            "x-hybris-auth": self.HYBRIS_AUTH
        })

        response = requests.request(
            method, f"{self.BASE_URL}{endpoint}", headers=headers, **kwargs
        )

        if response.status_code == 401:
            token = self.get_access_token(force_refresh=True)
            headers["Authorization"] = f"Bearer {token}"
            response = requests.request(
                method, f"{self.BASE_URL}{endpoint}", headers=headers, **kwargs
            )

        response.raise_for_status()
        return response.json()

    def search_sailings(
        self, departure: str, arrival: str, date: str,
        adults: int = 1, children: int = 0, seniors: int = 0,
        infants: int = 0, vehicle_type: Optional[str] = "UH"
    ) -> Dict:
        """Search for available sailings"""
        departure_code = self.TERMINALS.get(departure.lower(), departure.upper())
        arrival_code = self.TERMINALS.get(arrival.lower(), arrival.upper())

        passengers = []
        if adults > 0:
            passengers.append({"code": "adult", "quantity": adults})
        if children > 0:
            passengers.append({"code": "child", "quantity": children})
        if seniors > 0:
            passengers.append({"code": "senior", "quantity": seniors})
        if infants > 0:
            passengers.append({"code": "infant", "quantity": infants})

        is_walk_on = vehicle_type is None

        payload = {
            "routeDetails": {
                "departureLocation": departure_code,
                "arrivalLocation": arrival_code,
                "departureDate": date,
                "tripType": "SINGLE"
            },
            "passengerDetails": {
                "passengers": passengers,
                "travellingAsWalkOn": is_walk_on,
                "allowTAP": False,
                "allowVoucher": False,
                "carryingDangerousGoods": False
            },
            "vehicleDetails": {
                "vehicleTypeCode": vehicle_type or "UH",
                "height": 0,
                "length": 0,
                "carryingDangerousGoods": False,
                "vehicleWithSidecarOrTrailer": False,
                "carryingLivestock": False
            }
        }

        return self._make_request(
            "POST", "/api/ex/travel/sailings/1.0/search",
            headers={"Content-Type": "application/json"}, json=payload
        )

    def find_sailing(self, sailings_response: Dict, target_time: str) -> Optional[Dict]:
        """Find a specific sailing by departure time"""
        target_normalized = self._normalize_time(target_time)
        for sailing in sailings_response.get("sailingResults", {}).get("sailingDetails", []):
            sailing_time = sailing.get("departureTime", "")
            if self._normalize_time(sailing_time) == target_normalized:
                return sailing
        return None

    def _normalize_time(self, time_str: str) -> str:
        """Normalize time string for comparison"""
        time_str = time_str.lower().strip()
        if ":" in time_str and ("am" not in time_str and "pm" not in time_str):
            try:
                hour, minute = time_str.split(":")
                hour = int(hour)
                if hour >= 12:
                    return f"{hour-12 if hour > 12 else 12}:{minute} pm"
                else:
                    return f"{hour if hour > 0 else 12}:{minute} am"
            except:
                pass
        return time_str

    def is_sailing_available(self, sailing: Dict) -> bool:
        """Check if sailing has available spots"""
        status = sailing.get("sailingPrice", {}).get("status", "")
        return status == "AVAILABLE"


def wait_for_availability(
    departure: str,
    arrival: str,
    date: str,
    time: str,
    adults: int = 1,
    children: int = 0,
    seniors: int = 0,
    infants: int = 0,
    vehicle: bool = True,
    poll_interval: int = 60,
    timeout: int = 3600,
    verbose: bool = False
) -> Dict:
    """
    Poll BC Ferries API until the specified sailing becomes available.

    Returns:
        Dict with 'available' (bool), 'sailing' (dict if found), 'elapsed' (seconds)
    """
    api = BCFerriesAPI()
    start_time = time_module.time()
    checks = 0

    vehicle_type = "UH" if vehicle else None

    if verbose:
        print(f"Waiting for ferry availability:", file=sys.stderr)
        print(f"  Route: {departure} → {arrival}", file=sys.stderr)
        print(f"  Date: {date}", file=sys.stderr)
        print(f"  Time: {time}", file=sys.stderr)
        print(f"  Passengers: {adults} adults, {children} children, {seniors} seniors, {infants} infants", file=sys.stderr)
        print(f"  Vehicle: {'Yes' if vehicle else 'No (walk-on)'}", file=sys.stderr)
        print(f"  Poll interval: {poll_interval}s", file=sys.stderr)
        print(f"  Timeout: {timeout}s", file=sys.stderr)
        print("", file=sys.stderr)

    while True:
        checks += 1
        elapsed = time_module.time() - start_time

        if elapsed > timeout:
            if verbose:
                print(f"\nTimeout reached after {int(elapsed)}s ({checks} checks)", file=sys.stderr)
            return {
                "available": False,
                "reason": "timeout",
                "elapsed": elapsed,
                "checks": checks
            }

        try:
            if verbose:
                print(f"[Check #{checks}] Polling API...", file=sys.stderr, end=" ")

            result = api.search_sailings(
                departure=departure,
                arrival=arrival,
                date=date,
                adults=adults,
                children=children,
                seniors=seniors,
                infants=infants,
                vehicle_type=vehicle_type
            )

            sailing = api.find_sailing(result, time)

            if sailing:
                available = api.is_sailing_available(sailing)
                status = sailing.get("sailingPrice", {}).get("status", "UNKNOWN")
                price = sailing.get("sailingPrice", {}).get("fromPrice", "N/A")

                if verbose:
                    print(f"Status: {status}, Price: {price}", file=sys.stderr)

                if available:
                    if verbose:
                        print(f"\n✅ Ferry available! (after {int(elapsed)}s, {checks} checks)", file=sys.stderr)
                    return {
                        "available": True,
                        "sailing": sailing,
                        "elapsed": elapsed,
                        "checks": checks,
                        "price": price,
                        "status": status
                    }
                else:
                    if verbose:
                        print(f"Not available yet (status: {status})", file=sys.stderr)
            else:
                if verbose:
                    print(f"Sailing not found at {time}", file=sys.stderr)

        except Exception as e:
            if verbose:
                print(f"Error: {e}", file=sys.stderr)

        if verbose:
            print(f"Waiting {poll_interval}s before next check...", file=sys.stderr)

        time_module.sleep(poll_interval)


def main():
    parser = argparse.ArgumentParser(
        description="Wait for BC Ferries sailing availability",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Wait for 1:20pm sailing from Departure Bay to Horseshoe Bay
  wait-for-ferry --from "Departure Bay" --to "Horseshoe Bay" \\
    --date "10/15/2025" --time "1:20 pm" --adults 2 --vehicle

  # Walk-on passenger, check every 30 seconds
  wait-for-ferry --from tsawwassen --to swartz_bay \\
    --date "12/25/2025" --time "9:00 am" --no-vehicle \\
    --poll-interval 30

  # Family with children, 2 hour timeout
  wait-for-ferry --from nanaimo --to vancouver \\
    --date "01/01/2026" --time "3:00 pm" \\
    --adults 2 --children 2 --timeout 7200

Exit codes:
  0 - Sailing became available
  1 - Timeout reached (not available)
  2 - Invalid arguments or API error
        """
    )

    parser.add_argument("--from", dest="departure", required=True,
                        help="Departure terminal (e.g., 'Departure Bay', 'tsawwassen')")
    parser.add_argument("--to", dest="arrival", required=True,
                        help="Arrival terminal (e.g., 'Horseshoe Bay', 'swartz_bay')")
    parser.add_argument("--date", required=True,
                        help="Departure date in MM/DD/YYYY format (e.g., '10/15/2025')")
    parser.add_argument("--time", required=True,
                        help="Departure time (e.g., '1:20 pm', '13:20')")

    parser.add_argument("--adults", type=int, default=1,
                        help="Number of adults (12+) [default: 1]")
    parser.add_argument("--children", type=int, default=0,
                        help="Number of children (5-11) [default: 0]")
    parser.add_argument("--seniors", type=int, default=0,
                        help="Number of seniors (65+) [default: 0]")
    parser.add_argument("--infants", type=int, default=0,
                        help="Number of infants (0-4, free) [default: 0]")

    parser.add_argument("--vehicle", dest="vehicle", action="store_true", default=True,
                        help="Travelling with vehicle (default)")
    parser.add_argument("--no-vehicle", dest="vehicle", action="store_false",
                        help="Walk-on passenger (no vehicle)")

    parser.add_argument("--poll-interval", type=int, default=60,
                        help="Seconds between API checks [default: 60]")
    parser.add_argument("--timeout", type=int, default=3600,
                        help="Maximum wait time in seconds [default: 3600 (1 hour)]")

    parser.add_argument("-v", "--verbose", action="store_true",
                        help="Show detailed progress")
    parser.add_argument("-q", "--quiet", action="store_true",
                        help="Suppress all output (only exit code)")
    parser.add_argument("--json", action="store_true",
                        help="Output result as JSON")

    args = parser.parse_args()

    # Validate arguments
    if args.adults + args.children + args.seniors == 0:
        print("Error: Must have at least one passenger", file=sys.stderr)
        return 2

    if args.poll_interval < 10:
        print("Warning: Poll interval < 10s may hit rate limits", file=sys.stderr)

    try:
        result = wait_for_availability(
            departure=args.departure,
            arrival=args.arrival,
            date=args.date,
            time=args.time,
            adults=args.adults,
            children=args.children,
            seniors=args.seniors,
            infants=args.infants,
            vehicle=args.vehicle,
            poll_interval=args.poll_interval,
            timeout=args.timeout,
            verbose=args.verbose and not args.quiet
        )

        if args.json:
            # Output full result as JSON
            print(json.dumps(result, indent=2))
        elif not args.quiet:
            if result["available"]:
                print(f"✅ Ferry available!")
                print(f"Price: {result.get('price', 'N/A')}")
                print(f"Elapsed: {int(result['elapsed'])}s ({result['checks']} checks)")
            else:
                print(f"❌ Ferry not available (timeout after {int(result['elapsed'])}s)")

        return 0 if result["available"] else 1

    except Exception as e:
        if not args.quiet:
            print(f"Error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    import time as time_module
    sys.exit(main())
