#!/usr/bin/env python3
"""
Test script to verify Playwright Python bindings work correctly
"""

from playwright.sync_api import sync_playwright
import sys

def test_playwright():
    """Test basic Playwright functionality"""
    print("🧪 Testing Playwright Python bindings...")

    try:
        with sync_playwright() as p:
            print("  ✓ Playwright context created")

            # Launch browser
            browser = p.chromium.launch(headless=True)
            print("  ✓ Chromium browser launched")

            # Create page
            page = browser.new_page()
            print("  ✓ New page created")

            # Navigate to a test URL
            page.goto("https://example.com")
            print("  ✓ Navigation successful")

            # Get page title
            title = page.title()
            print(f"  ✓ Page title: {title}")

            # Take screenshot
            page.screenshot(path="/tmp/test-screenshot.png")
            print("  ✓ Screenshot saved to /tmp/test-screenshot.png")

            # Close browser
            browser.close()
            print("  ✓ Browser closed")

        print("\n✅ All tests passed!")
        return 0

    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(test_playwright())
