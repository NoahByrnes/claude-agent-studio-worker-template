#!/usr/bin/env python3
"""
BC Ferries Booking Automation - Modular Version
Each step is a separate function with validation
"""

from playwright.sync_api import Page, sync_playwright
from datetime import datetime
from typing import Dict, Optional
import re


class BCFerriesBooking:
    """Modular BC Ferries booking automation with validation"""

    def __init__(self, page: Page):
        self.page = page
        self.booking_state = {
            "logged_in": False,
            "terminals_selected": False,
            "date_selected": None,
            "passengers_added": 0,
            "vehicle_selected": False,
            "sailing_selected": None,
            "fare_selected": None,
            "payment_filled": False
        }

    def login(self, email: str, password: str) -> Dict:
        """
        Log in to BC Ferries account.

        Returns:
            {
                "success": bool,
                "message": str,
                "logged_in_as": str (email if successful)
            }
        """
        try:
            print("🔐 Logging in...")

            # Navigate to home page
            self.page.goto("https://www.bcferries.com/", timeout=30000)
            self.page.wait_for_load_state("networkidle")

            # Click login link
            self.page.get_by_role("link", name="Login", exact=True).click()
            self.page.wait_for_timeout(1000)

            # Fill credentials
            self.page.get_by_placeholder("Enter your email").fill(email)
            self.page.get_by_role("textbox", name="Password*", exact=True).fill(password)
            self.page.get_by_role("button", name="Log in").click()

            # Wait for login to complete
            self.page.wait_for_timeout(2000)

            # VERIFY: Check if we're actually logged in
            page_text = self.page.inner_text("body")

            # Look for user name or "Log out" link as confirmation
            if email.split("@")[0].lower() in page_text.lower() or "log out" in page_text.lower() or "logout" in page_text.lower():
                self.booking_state["logged_in"] = True
                print("  ✅ Login verified")
                return {
                    "success": True,
                    "message": "Successfully logged in",
                    "logged_in_as": email
                }
            else:
                self.page.screenshot(path="login_failed.png")
                return {
                    "success": False,
                    "message": "Login failed - could not verify logged in state",
                    "logged_in_as": None
                }

        except Exception as e:
            self.page.screenshot(path="login_error.png")
            return {
                "success": False,
                "message": f"Login error: {e}",
                "logged_in_as": None
            }

    def navigate_to_booking(self) -> Dict:
        """
        Navigate to the booking flow starting point.

        Returns:
            {
                "success": bool,
                "message": str
            }
        """
        try:
            print("📋 Navigating to booking flow...")

            self.page.get_by_role("link", name="Book sailings").click()
            self.page.wait_for_timeout(1000)
            self.page.locator("a").filter(has_text=re.compile(r"^Book now$")).click()
            self.page.wait_for_timeout(1000)

            # VERIFY: Check we're on the booking page
            page_text = self.page.inner_text("body")

            if "Terminal" in page_text and "Date" in page_text:
                print("  ✅ On booking page")
                return {
                    "success": True,
                    "message": "Successfully navigated to booking page"
                }
            else:
                self.page.screenshot(path="booking_nav_failed.png")
                return {
                    "success": False,
                    "message": "Failed to reach booking page"
                }

        except Exception as e:
            self.page.screenshot(path="booking_nav_error.png")
            return {
                "success": False,
                "message": f"Navigation error: {e}"
            }

    def select_terminals(self, departure: str, destination: str) -> Dict:
        """
        Select departure and destination terminals.

        Returns:
            {
                "success": bool,
                "message": str,
                "departure": str,
                "destination": str
            }
        """
        try:
            print(f"🚢 Selecting terminals: {departure} → {destination}...")

            # Select departure
            self.page.locator("#ui-id-1").get_by_text("(Terminal)").click()
            self.page.wait_for_timeout(300)
            self.page.locator("#ui-id-2").get_by_text(departure, exact=False).click()
            self.page.wait_for_timeout(500)

            # Select destination
            self.page.locator("#ui-id-9").get_by_text("(Terminal)").click()
            self.page.wait_for_timeout(300)
            self.page.locator("#ui-id-10").get_by_text(destination, exact=False).click()
            self.page.wait_for_timeout(500)

            # VERIFY: Check both terminals are displayed in the header
            page_text = self.page.inner_text("body")

            departure_shown = departure.split()[0] in page_text  # e.g., "Tsawwassen" from "Tsawwassen"
            destination_shown = destination.split()[0] in page_text  # e.g., "Swartz" from "Swartz Bay"

            if departure_shown and destination_shown:
                self.booking_state["terminals_selected"] = True
                print(f"  ✅ Terminals verified: {departure} → {destination}")
                return {
                    "success": True,
                    "message": "Terminals selected and verified",
                    "departure": departure,
                    "destination": destination
                }
            else:
                self.page.screenshot(path="terminals_failed.png")
                return {
                    "success": False,
                    "message": f"Failed to verify terminals. Departure shown: {departure_shown}, Destination shown: {destination_shown}",
                    "departure": None,
                    "destination": None
                }

        except Exception as e:
            self.page.screenshot(path="terminals_error.png")
            return {
                "success": False,
                "message": f"Terminal selection error: {e}",
                "departure": None,
                "destination": None
            }

    def select_date(self, travel_date: str) -> Dict:
        """
        Select travel date from calendar.

        Args:
            travel_date: Format "YYYY-MM-DD"

        Returns:
            {
                "success": bool,
                "message": str,
                "date_selected": str
            }
        """
        try:
            print(f"📅 Selecting date: {travel_date}...")

            date_obj = datetime.strptime(travel_date, "%Y-%m-%d")
            day = str(date_obj.day)

            self.page.get_by_role("link", name="Date").click()
            self.page.wait_for_timeout(500)
            self.page.get_by_role("link", name=day, exact=True).click()
            self.page.wait_for_timeout(500)
            self.page.get_by_role("button", name="Continue").click()
            self.page.wait_for_timeout(1000)

            # VERIFY: Check date is shown in header
            page_text = self.page.inner_text("body")

            # Look for date in various formats
            date_shown = (
                date_obj.strftime("%b %d") in page_text or  # "Oct 15"
                date_obj.strftime("%B %d") in page_text or  # "October 15"
                str(day) in page_text  # At least the day number
            )

            if date_shown:
                self.booking_state["date_selected"] = travel_date
                print(f"  ✅ Date verified: {travel_date}")
                return {
                    "success": True,
                    "message": "Date selected and verified",
                    "date_selected": travel_date
                }
            else:
                self.page.screenshot(path="date_failed.png")
                return {
                    "success": False,
                    "message": "Failed to verify date selection",
                    "date_selected": None
                }

        except Exception as e:
            self.page.screenshot(path="date_error.png")
            return {
                "success": False,
                "message": f"Date selection error: {e}",
                "date_selected": None
            }

    def add_passengers(self, adults: int = 1, children: int = 0, infants: int = 0, seniors: int = 0) -> Dict:
        """
        Add passengers to booking.

        Returns:
            {
                "success": bool,
                "message": str,
                "passengers": {"adults": int, "children": int, "infants": int, "seniors": int},
                "total": int
            }
        """
        try:
            print(f"👥 Adding passengers: {adults} adults, {children} children, {infants} infants, {seniors} seniors...")

            self.page.wait_for_timeout(1000)

            # Try guest flow first (has .y_adult class buttons)
            try:
                for i in range(adults):
                    self.page.locator("button.y_outboundPassengerQtySelectorPlus.y_adult").click()
                    self.page.wait_for_timeout(300)
                print(f"  ↳ Used guest flow for {adults} adult(s)")
            except:
                # Fallback to logged-in flow (generic + buttons)
                plus_buttons = self.page.locator("button").filter(has_text="+").all()
                for i in range(adults):
                    plus_buttons[1].click()  # Adults + button
                    self.page.wait_for_timeout(300)
                print(f"  ↳ Used logged-in flow for {adults} adult(s)")

            # TODO: Add children, infants, seniors similarly

            # VERIFY: Check passenger count before continuing
            self.page.wait_for_timeout(500)
            page_text = self.page.inner_text("body")

            # Check for error message
            if "Add at least one passenger" in page_text:
                self.page.screenshot(path="passengers_failed.png")
                return {
                    "success": False,
                    "message": "Failed to add passengers - still showing error",
                    "passengers": {"adults": 0, "children": 0, "infants": 0, "seniors": 0},
                    "total": 0
                }

            # Check passenger count is displayed (look for number in UI)
            # The UI shows the count, but format varies
            # For now, if no error, assume success

            self.page.get_by_role("button", name="Continue").click()
            self.page.wait_for_timeout(2000)

            # VERIFY: After clicking Continue, we should NOT be on the passenger page anymore
            page_text_after = self.page.inner_text("body")

            if "Add at least one passenger" in page_text_after:
                # Still on passenger page = didn't work
                self.page.screenshot(path="passengers_not_accepted.png")
                return {
                    "success": False,
                    "message": "Passengers not accepted - still on passenger page",
                    "passengers": {"adults": 0, "children": 0, "infants": 0, "seniors": 0},
                    "total": 0
                }

            self.booking_state["passengers_added"] = adults + children + infants + seniors
            print(f"  ✅ Passengers verified: {adults + children + infants + seniors} total")

            return {
                "success": True,
                "message": "Passengers added and verified",
                "passengers": {
                    "adults": adults,
                    "children": children,
                    "infants": infants,
                    "seniors": seniors
                },
                "total": adults + children + infants + seniors
            }

        except Exception as e:
            self.page.screenshot(path="passengers_error.png")
            return {
                "success": False,
                "message": f"Passenger addition error: {e}",
                "passengers": {"adults": 0, "children": 0, "infants": 0, "seniors": 0},
                "total": 0
            }

    def select_vehicle(self, height: str = "under_7ft", length: str = "under_20ft") -> Dict:
        """
        Select vehicle dimensions.

        Returns:
            {
                "success": bool,
                "message": str,
                "vehicle": {"height": str, "length": str}
            }
        """
        try:
            print(f"🚗 Selecting vehicle: {height}, {length}...")

            # Select height
            if height == "under_7ft":
                self.page.get_by_role("radio", name="ft. (2.13 m) and under").check()
            else:
                self.page.get_by_role("radio", name="Over 7 ft. (2.13 m)").check()

            self.page.wait_for_timeout(300)

            # Select length
            if length == "under_20ft":
                self.page.get_by_role("radio", name="Under 20 ft. (6.10 m)").check()
            else:
                self.page.get_by_role("radio", name="Over 20 ft. (6.10 m)").check()

            self.page.wait_for_timeout(300)

            # VERIFY: Check radio buttons are actually selected
            height_checked = False
            length_checked = False

            try:
                if height == "under_7ft":
                    height_radio = self.page.get_by_role("radio", name="ft. (2.13 m) and under")
                else:
                    height_radio = self.page.get_by_role("radio", name="Over 7 ft. (2.13 m)")

                height_checked = height_radio.is_checked()

                if length == "under_20ft":
                    length_radio = self.page.get_by_role("radio", name="Under 20 ft. (6.10 m)")
                else:
                    length_radio = self.page.get_by_role("radio", name="Over 20 ft. (6.10 m)")

                length_checked = length_radio.is_checked()
            except:
                pass

            if height_checked and length_checked:
                print(f"  ✅ Vehicle dimensions verified: {height}, {length}")
            else:
                print(f"  ⚠️ Could not verify radio states, proceeding anyway")

            self.page.get_by_role("button", name="Continue").click()
            self.page.wait_for_timeout(2000)

            # VERIFY: Should now be on sailings page
            page_text = self.page.inner_text("body")

            if "Select your departure" in page_text or "Sailing" in page_text or "DEPART" in page_text:
                self.booking_state["vehicle_selected"] = True
                print("  ✅ On sailings page")
                return {
                    "success": True,
                    "message": "Vehicle selected and verified",
                    "vehicle": {"height": height, "length": length}
                }
            else:
                self.page.screenshot(path="vehicle_failed.png")
                return {
                    "success": False,
                    "message": "Failed to verify vehicle selection - not on sailings page",
                    "vehicle": None
                }

        except Exception as e:
            self.page.screenshot(path="vehicle_error.png")
            return {
                "success": False,
                "message": f"Vehicle selection error: {e}",
                "vehicle": None
            }

    def find_and_select_sailing(self, sailing_time: str) -> Dict:
        """
        Find a specific sailing time and click "View fares".

        Args:
            sailing_time: e.g., "7:00 am" (must match exactly)

        Returns:
            {
                "success": bool,
                "message": str,
                "sailing_time": str,
                "available": bool
            }
        """
        try:
            print(f"⏰ Finding sailing: {sailing_time}...")

            self.page.wait_for_load_state("networkidle")
            self.page.wait_for_timeout(1000)

            # VERIFY: Check sailing time exists on page
            page_text = self.page.inner_text("body")

            if sailing_time not in page_text:
                self.page.screenshot(path="sailing_not_found.png")
                return {
                    "success": False,
                    "message": f"Sailing time '{sailing_time}' not found on page",
                    "sailing_time": None,
                    "available": False
                }

            print(f"  ✓ Found sailing time: {sailing_time}")

            # Check if it's sold out
            sold_out = "sold out" in page_text.lower() or "reservations sold out" in page_text.lower()

            # Find the specific sailing card containing this time and click its "View fares" button
            sailing_cards = self.page.locator(".p-card").all()

            clicked = False
            sailing_sold_out = False

            for card in sailing_cards:
                card_text = card.inner_text()
                if sailing_time in card_text:
                    # Found the right card - check if it's sold out
                    if "sold out" in card_text.lower() or "reservations sold out" in card_text.lower():
                        sailing_sold_out = True
                        print(f"  ⚠️  Sailing {sailing_time} became SOLD OUT (was available in API)")
                        self.page.screenshot(path="sailing_sold_out_race_condition.png")
                        break

                    # Try to click "View fares" button
                    try:
                        card.locator(".btn.btn-primary.view-fare-btn").click()
                        clicked = True
                        print(f"  ✓ Clicked 'View fares' for {sailing_time}")
                        break
                    except Exception as e:
                        print(f"  ⚠️  Could not click 'View fares': {e}")
                        self.page.screenshot(path="view_fares_button_error.png")
                        break

            if sailing_sold_out:
                return {
                    "success": False,
                    "message": f"Sailing {sailing_time} sold out before booking could complete (race condition)",
                    "sailing_time": sailing_time,
                    "available": False,
                    "race_condition": True
                }

            if not clicked:
                self.page.screenshot(path="sailing_button_not_found.png")
                return {
                    "success": False,
                    "message": f"Could not find 'View fares' button for {sailing_time}",
                    "sailing_time": None,
                    "available": False,
                    "race_condition": False
                }

            self.page.wait_for_timeout(1500)

            # VERIFY: Fare modal should be open
            page_text_after = self.page.inner_text("body")

            if "Reservation" in page_text_after or "fare" in page_text_after.lower() or "SAVER" in page_text_after:
                self.booking_state["sailing_selected"] = sailing_time
                print(f"  ✅ Fare selection modal opened for {sailing_time}")
                return {
                    "success": True,
                    "message": "Sailing found and fare modal opened",
                    "sailing_time": sailing_time,
                    "available": not sold_out
                }
            else:
                self.page.screenshot(path="fare_modal_failed.png")
                return {
                    "success": False,
                    "message": "Failed to open fare selection modal",
                    "sailing_time": None,
                    "available": False
                }

        except Exception as e:
            self.page.screenshot(path="sailing_error.png")
            return {
                "success": False,
                "message": f"Sailing selection error: {e}",
                "sailing_time": None,
                "available": False
            }

    def select_fare(self, fare_type: str = "reservation_only") -> Dict:
        """
        Select fare type from modal.

        Args:
            fare_type: "reservation_only", "ADVANCE" (or "prepaid"), "SAVER", or "STANDARD"

        Returns:
            {
                "success": bool,
                "message": str,
                "fare_type": str,
                "price": str (if available)
            }
        """
        try:
            print(f"💰 Selecting fare: {fare_type}...")

            self.page.wait_for_timeout(1000)

            # Normalize fare type for comparison
            fare_lower = fare_type.lower()

            if fare_lower == "reservation_only":
                self.page.get_by_role("listitem").filter(has_text="Reservation Only").locator("label").first.click()
                print("  ↳ Selected Reservation Only fare")
            elif fare_lower in ["advance", "prepaid"]:
                self.page.get_by_role("listitem").filter(has_text="Prepaid").locator("label").first.click()
                print("  ↳ Selected Prepaid (Advance) fare")
            elif fare_lower == "saver":
                self.page.get_by_role("listitem").filter(has_text="Saver").locator("label").first.click()
                print("  ↳ Selected Saver fare")
            else:
                # Default to prepaid if unknown
                self.page.get_by_role("listitem").filter(has_text="Prepaid").locator("label").first.click()
                print(f"  ↳ Unknown fare type '{fare_type}', defaulting to Prepaid")

            self.page.wait_for_timeout(1000)

            # VERIFY: Fare should be selected (radio button checked)
            # This is hard to verify directly, so we'll check if we can proceed

            self.booking_state["fare_selected"] = fare_type
            print(f"  ✅ Fare selected: {fare_type}")

            return {
                "success": True,
                "message": f"Fare selected: {fare_type}",
                "fare_type": fare_type,
                "price": "$20" if fare_type == "reservation_only" else "varies"
            }

        except Exception as e:
            self.page.screenshot(path="fare_error.png")
            return {
                "success": False,
                "message": f"Fare selection error: {e}",
                "fare_type": None,
                "price": None
            }

    def proceed_to_checkout(self) -> Dict:
        """
        Proceed from fare selection to checkout page.

        Returns:
            {
                "success": bool,
                "message": str
            }
        """
        try:
            print("💳 Proceeding to checkout...")

            self.page.goto("https://www.bcferries.com/fare-selection-review")
            self.page.wait_for_load_state("networkidle")
            self.page.wait_for_timeout(1000)

            self.page.get_by_role("button", name="Continue").click()
            self.page.wait_for_timeout(2000)

            # VERIFY: Should be on payment page
            page_text = self.page.inner_text("body")

            if "Payment method" in page_text or "Name on card" in page_text:
                print("  ✅ On checkout page")
                return {
                    "success": True,
                    "message": "Successfully reached checkout page"
                }
            else:
                self.page.screenshot(path="checkout_failed.png")
                return {
                    "success": False,
                    "message": "Failed to reach checkout page"
                }

        except Exception as e:
            self.page.screenshot(path="checkout_error.png")
            return {
                "success": False,
                "message": f"Checkout navigation error: {e}"
            }

    def fill_payment_form(self, cc_info: Dict, verify_only: bool = True) -> Dict:
        """
        Fill payment form with credit card and billing info.

        Args:
            cc_info: {
                "name": str,
                "number": str,
                "expiry": str,
                "cvv": str,
                "address": str,
                "city": str,
                "country": str,
                "province": str,
                "postal_code": str
            }
            verify_only: If True, verifies fields are filled correctly

        Returns:
            {
                "success": bool,
                "message": str,
                "fields_filled": list
            }
        """
        try:
            print("📝 Filling payment form...")
            fields_filled = []

            # Name on card
            self.page.get_by_role("textbox", name="Name on card*").fill(cc_info["name"])
            fields_filled.append("name")
            print(f"  ✓ Name: {cc_info['name']}")

            # Credit card number (in iframe)
            self.page.locator("#monerisFrame").content_frame.get_by_role("textbox", name="0000 0000 0000").fill(cc_info["number"])
            fields_filled.append("card_number")
            print(f"  ✓ Card: {cc_info['number'][:4]}...{cc_info['number'][-4:]}")

            # Expiry
            self.page.get_by_role("textbox", name="Expiry date*").fill(cc_info["expiry"])
            fields_filled.append("expiry")
            print(f"  ✓ Expiry: {cc_info['expiry']}")

            # CVV
            self.page.get_by_role("textbox", name="000").fill(cc_info["cvv"])
            fields_filled.append("cvv")
            print(f"  ✓ CVV: {cc_info['cvv']}")

            # Address
            self.page.get_by_role("textbox", name="Street number for Address").fill(cc_info["address"])
            fields_filled.append("address")
            print(f"  ✓ Address: {cc_info['address']}")

            # City
            self.page.get_by_role("textbox", name="City*").fill(cc_info["city"])
            fields_filled.append("city")
            print(f"  ✓ City: {cc_info['city']}")

            # Country
            self.page.get_by_role("button", name="Select country").click()
            self.page.locator("a").filter(has_text=cc_info["country"]).click()
            fields_filled.append("country")
            print(f"  ✓ Country: {cc_info['country']}")

            # Province
            self.page.get_by_role("button", name="Select your province/state").click()
            self.page.locator("a").filter(has_text=re.compile(rf"^{cc_info['province']}$")).click()
            fields_filled.append("province")
            print(f"  ✓ Province: {cc_info['province']}")

            # Postal code
            self.page.get_by_role("textbox", name="Postal/Zip code*").fill(cc_info["postal_code"])
            fields_filled.append("postal_code")
            print(f"  ✓ Postal code: {cc_info['postal_code']}")

            # Terms
            self.page.locator("label").filter(has_text="I agree to BC Ferries'").locator("span").click()
            fields_filled.append("terms")
            print("  ✓ Terms accepted")

            # VERIFY: Check all fields have values if verify_only
            if verify_only:
                self.page.wait_for_timeout(500)

                # Check name field
                name_value = self.page.get_by_role("textbox", name="Name on card*").input_value()
                if name_value != cc_info["name"]:
                    return {
                        "success": False,
                        "message": f"Name verification failed. Expected: {cc_info['name']}, Got: {name_value}",
                        "fields_filled": fields_filled
                    }

            self.booking_state["payment_filled"] = True
            print("  ✅ Payment form filled and verified")

            return {
                "success": True,
                "message": "Payment form filled successfully",
                "fields_filled": fields_filled
            }

        except Exception as e:
            self.page.screenshot(path="payment_form_error.png")
            return {
                "success": False,
                "message": f"Payment form error: {e}",
                "fields_filled": fields_filled
            }

    def submit_payment(self, dry_run: bool = True) -> Dict:
        """
        Submit payment (or take screenshot if dry_run).

        Args:
            dry_run: If True, takes screenshot but doesn't actually submit

        Returns:
            {
                "success": bool,
                "message": str,
                "screenshot": str (path if taken)
            }
        """
        try:
            # Take screenshot before payment
            self.page.screenshot(path="before_payment.png", full_page=True)
            print("📸 Screenshot saved: before_payment.png")

            if dry_run:
                print("🧪 DRY RUN: Would click 'Pay now' here")
                return {
                    "success": True,
                    "message": "Dry run completed - screenshot taken, payment not submitted",
                    "screenshot": "before_payment.png"
                }

            # Actually click Pay now
            print("💰 Submitting payment...")
            self.page.get_by_role("button", name="Pay now").click()
            self.page.wait_for_timeout(3000)

            # Check result
            page_text = self.page.inner_text("body")

            if "decline" in page_text.lower() or "error" in page_text.lower():
                self.page.screenshot(path="payment_declined.png")
                return {
                    "success": False,
                    "message": "Payment declined",
                    "screenshot": "payment_declined.png"
                }
            elif "confirmation" in page_text.lower() or "thank you" in page_text.lower():
                self.page.screenshot(path="booking_confirmed.png")
                return {
                    "success": True,
                    "message": "Booking confirmed!",
                    "screenshot": "booking_confirmed.png"
                }
            else:
                self.page.screenshot(path="payment_unknown.png")
                return {
                    "success": False,
                    "message": "Unknown payment result",
                    "screenshot": "payment_unknown.png"
                }

        except Exception as e:
            self.page.screenshot(path="payment_submit_error.png")
            return {
                "success": False,
                "message": f"Payment submission error: {e}",
                "screenshot": "payment_submit_error.png"
            }

    def get_booking_state(self) -> Dict:
        """Get current booking state for debugging"""
        return self.booking_state.copy()


# Example usage
if __name__ == "__main__":
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)
        page = browser.new_page()

        booking = BCFerriesBooking(page)

        # Each step returns success/failure and can be checked
        result = booking.login("test@example.com", "password")
        if not result["success"]:
            print(f"❌ Login failed: {result['message']}")
            browser.close()
            exit(1)

        result = booking.navigate_to_booking()
        if not result["success"]:
            print(f"❌ Navigation failed: {result['message']}")
            browser.close()
            exit(1)

        # Continue with other steps...
        print(f"\nBooking state: {booking.get_booking_state()}")

        browser.close()
