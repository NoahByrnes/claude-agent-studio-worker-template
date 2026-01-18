#!/usr/bin/env python3
"""
BC Ferries Auto-Booking Script
Runs in E2B worker when ferry becomes available

Environment variables required:
- DEPARTURE: Departure terminal (e.g., "Departure Bay")
- ARRIVAL: Arrival terminal (e.g., "Horseshoe Bay")
- DATE: Travel date (YYYY-MM-DD)
- SAILING_TIME: Sailing time (e.g., "1:10 pm")
- ADULTS: Number of adults (default: 1)
- CHILDREN: Number of children (default: 0)
- SENIORS: Number of seniors (default: 0)
- VEHICLE_HEIGHT: Vehicle height (default: "under_7ft")
- VEHICLE_LENGTH: Vehicle length (default: "under_20ft")
- BC_FERRIES_EMAIL: BC Ferries account email
- BC_FERRIES_PASSWORD: BC Ferries account password
- CC_NAME: Cardholder name
- CC_NUMBER: Credit card number
- CC_EXPIRY: Expiry (MM/YY format)
- CC_CVV: CVV code
- CC_ADDRESS: Billing address
- CC_CITY: City
- CC_PROVINCE: Province/State
- CC_POSTAL: Postal/ZIP code
- DRY_RUN: Set to "true" to test without submitting payment (default: "true")
"""

import os
import sys
import json
from playwright.sync_api import sync_playwright
from bc_ferries_booking_modular import BCFerriesBooking

def main():
    # Get parameters from environment
    departure = os.environ.get('DEPARTURE')
    arrival = os.environ.get('ARRIVAL')
    date = os.environ.get('DATE')
    sailing_time = os.environ.get('SAILING_TIME')
    adults = int(os.environ.get('ADULTS', '1'))
    children = int(os.environ.get('CHILDREN', '0'))
    seniors = int(os.environ.get('SENIORS', '0'))
    vehicle_height = os.environ.get('VEHICLE_HEIGHT', 'under_7ft')
    vehicle_length = os.environ.get('VEHICLE_LENGTH', 'under_20ft')

    # Validate required parameters
    if not all([departure, arrival, date, sailing_time]):
        print("❌ Error: Missing required parameters")
        print("Required: DEPARTURE, ARRIVAL, DATE, SAILING_TIME")
        return {
            "success": False,
            "error": "Missing required parameters"
        }

    # Get credentials
    email = os.environ.get('BC_FERRIES_EMAIL')
    password = os.environ.get('BC_FERRIES_PASSWORD')

    if not email or not password:
        print("❌ Error: Missing BC Ferries credentials")
        return {
            "success": False,
            "error": "Missing BC_FERRIES_EMAIL or BC_FERRIES_PASSWORD"
        }

    # Build credit card info
    cc_info = {
        "name": os.environ.get('CC_NAME', ''),
        "number": os.environ.get('CC_NUMBER', ''),
        "expiry": os.environ.get('CC_EXPIRY', ''),
        "cvv": os.environ.get('CC_CVV', ''),
        "address": os.environ.get('CC_ADDRESS', ''),
        "city": os.environ.get('CC_CITY', ''),
        "country": os.environ.get('CC_COUNTRY', 'Canada'),
        "province": os.environ.get('CC_PROVINCE', ''),
        "postal_code": os.environ.get('CC_POSTAL', ''),
    }

    # Check if dry run mode
    dry_run = os.environ.get('DRY_RUN', 'true').lower() == 'true'

    print(f"🚢 BC Ferries Auto-Booking")
    print(f"   Route: {departure} → {arrival}")
    print(f"   Date: {date}")
    print(f"   Sailing: {sailing_time}")
    print(f"   Passengers: {adults} adults, {children} children, {seniors} seniors")
    print(f"   Mode: {'DRY RUN (no payment)' if dry_run else 'LIVE (will submit payment)'}")
    print()

    with sync_playwright() as p:
        # Launch browser (headless in production)
        headless = os.environ.get('HEADLESS', 'true').lower() == 'true'
        browser = p.chromium.launch(headless=headless)
        page = browser.new_page()
        booking = BCFerriesBooking(page)

        # Execute booking steps
        steps = [
            ("login", lambda: booking.login(email, password)),
            ("navigate", lambda: booking.navigate_to_booking()),
            ("terminals", lambda: booking.select_terminals(departure, arrival)),
            ("date", lambda: booking.select_date(date)),
            ("passengers", lambda: booking.add_passengers(adults=adults, children=children, seniors=seniors)),
            ("vehicle", lambda: booking.select_vehicle(vehicle_height, vehicle_length)),
            ("sailing", lambda: booking.find_and_select_sailing(sailing_time)),
            ("fare", lambda: booking.select_fare("reservation_only")),
            ("checkout", lambda: booking.proceed_to_checkout()),
            ("payment", lambda: booking.fill_payment_form(cc_info)),
            ("submit", lambda: booking.submit_payment(dry_run=dry_run)),
        ]

        result = {"success": True}

        for step_name, step_func in steps:
            print(f"[{step_name}] Starting...")
            step_result = step_func()

            if not step_result["success"]:
                print(f"❌ Failed at: {step_name}")
                print(f"   Error: {step_result['message']}")

                result = {
                    "success": False,
                    "failedStep": step_name,
                    "error": step_result["message"],
                    "raceCondition": step_result.get("race_condition", False)
                }
                break

            print(f"✅ {step_name} completed")

        if result["success"]:
            print("\n🎉 Booking automation completed successfully!")
            if dry_run:
                print("   (DRY RUN - payment was NOT submitted)")
            result["confirmationNumber"] = "DRY_RUN" if dry_run else "LIVE_BOOKING"

        browser.close()

    return result

if __name__ == "__main__":
    result = main()

    # Output JSON result for Stu to parse
    print("\n__RESULT__")
    print(json.dumps(result, indent=2))

    # Exit with appropriate code
    sys.exit(0 if result["success"] else 1)
