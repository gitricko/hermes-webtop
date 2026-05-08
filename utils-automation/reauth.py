import sys
import os
import re
import subprocess
import asyncio
from pathlib import Path
from playwright.async_api import async_playwright
from playwright_stealth import Stealth

SERVICE_DIR = Path.home() / ".google-oauth-automation"
PROFILE_DIR = SERVICE_DIR / "chrome-profile"
LOGIN_FLAG = SERVICE_DIR / "logged-in"

# Check if DEBUG environment variable is set
IS_DEBUG = os.environ.get("DEBUG") is not None


async def auto_click(page):
    """Attempt to automatically click through the Google OAuth flow"""
    # 1. Click account if chooser is present
    try:
        # Give it a moment to load
        await page.wait_for_selector("div[data-identifier], div[data-authuser='0']", timeout=3000)
        elements = await page.query_selector_all("div[data-identifier], div[data-authuser='0']")
        for el in elements:
            if await el.is_visible():
                await el.click()
                print("✅ Auto-selected account.")
                break
    except Exception:
        pass

    # 2. Click Continue/Allow on consent screen
    try:
        # Google's continue buttons often use span inside a button
        await page.wait_for_selector("button span:has-text('Sign In'), button span:has-text('Allow')", timeout=3000)
        elements = await page.query_selector_all("button:has-text('Sign In'), button:has-text('Allow')")
        for el in elements:
            if await el.is_visible():
                await el.click()
                print("✅ Auto-clicked Continue/Allow.")
                break
    except Exception:
        pass


async def main():
    # 1. Start the hermes process
    cmd = ["hermes", "auth", "login", "--device-code", "--provider", "google-antigravity"]
    # Capture both stdout and stderr as some tools print URLs to stderr
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    auth_url = None
    url_pattern = r'https://accounts\.google\.com/o/oauth2/v2/auth\?\S+'

    print("Starting hermes and watching for URL...")

    # 2. Read output line by line to find the URL
    for line in iter(process.stdout.readline, ''):
        match = re.search(url_pattern, line)
        if match:
            auth_url = match.group(0)
            print(f"Captured URL: {auth_url}")
            break
    
    if not auth_url:
        print("Failed to capture URL.")
        return
    uri = auth_url

    
    SERVICE_DIR.mkdir(parents=True, exist_ok=True)
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    
    first_time = not LOGIN_FLAG.exists()
    # If DEBUG is set, we ignore the LOGIN_FLAG and treat it as a visible run
    is_headless = False if (first_time or IS_DEBUG) else True
    
    print(f"🚀 Starting automation (First time: {first_time} | Debug: {IS_DEBUG})")
    print(f"🔗 Target URI: {uri}")

    async with Stealth().use_async(async_playwright()) as p:
        # Construct arguments based on headlessness
        headless_args = []
        if is_headless:
            headless_args.append("--headless=new")

        context = await p.chromium.launch_persistent_context(
            executable_path="/usr/bin/chromium",
            user_data_dir=str(PROFILE_DIR),
            headless=False if (not is_headless) else True,
            channel="chrome",
            user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
            args=[
                "--disable-blink-features=AutomationControlled",
                "--disable-extensions",
                "--disable-infobars",
                *headless_args
            ],
            viewport={"width": 1280, "height": 900},
        )
        
        page = await context.new_page()
        
        
        # Flag to indicate success based on redirect detection
        success = False

        # Event handler to detect navigation to localhost
        async def on_framenavigated(frame):
            nonlocal success
            url = frame.url
            if url.startswith("http://localhost") or url.startswith("http://127.0.0.1"):
                success = True

        page.on("framenavigated", on_framenavigated)

        try:
            await page.goto(uri)
        except Exception as e:
            # If the background CLI server gets the request and shuts down localhost too quickly, Playwright throws an exception
            if "localhost" in str(e) or "127.0.0.1" in str(e) or "ERR_CONNECTION_REFUSED" in str(e):
                success = True
            else:
                pass # Continue handling below

        if first_time:
            print("\n📌 Please log into your Google account and complete the flow manually.")
            print("   Waiting for redirect to localhost/127.0.0.1...\n")
            
            # Wait for user to manually complete
            for _ in range(600): # 10 minutes timeout
                if success:
                    LOGIN_FLAG.write_text("ok")
                    print("✅ Login completed and saved! You will not have to do this again.")
                    break
                # Additionally check the page url in case event didn't fire
                try:
                    if page.url.startswith("http://localhost") or page.url.startswith("http://127.0.0.1"):
                        LOGIN_FLAG.write_text("ok")
                        print("✅ Login completed and saved! You will not have to do this again.")
                        success = True
                        break
                except:
                    pass

                await asyncio.sleep(1)
            
            if not success:
                print("❌ Timeout waiting for auth completion.")
        else:
            print("🤖 Running headless automation...")
            
            # loop until redirect
            for _ in range(30): # 30 seconds max
                if success:
                    print("✅ Headless auth completed via redirect!")
                    break
                
                try:
                    if page.url.startswith("http://localhost") or page.url.startswith("http://127.0.0.1"):
                        print("✅ Headless auth completed!")
                        success = True
                        break
                except:
                    pass
                    
                # attempt auto clicking
                print("   Checking for account chooser or consent screen...")
                await auto_click(page)
                await asyncio.sleep(1)
                
            if not success:
                 print("⚠️ Timeout: Failed to reach localhost redirect automatically.")

        # Cleanup
        try:
            await page.close()
            await context.close()
        except:
            pass

if __name__ == "__main__":
    asyncio.run(main())
