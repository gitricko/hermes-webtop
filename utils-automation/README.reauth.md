# Hermes Provider Authentication Utilities

This directory contains utility scripts designed to automate and enhance authentication flows for the Hermes project.

## `reauth.py` - Automated Google OAuth Sessions

`reauth.py` is a Python automation script that uses [Playwright](https://playwright.dev/python/) to manage Google OAuth sessions seamlessly. It wraps around the `hermes auth login` command to automate the browser-based authorization step, supporting an initial interactive login followed by subsequent headless, automatic re-authentications.

### Features

- **Initial Interactive Login:** On the very first run, it opens a visible Chromium browser instance. This allows the user to securely enter their Google credentials and manually approve the OAuth consent screen.
- **Persistent Browsing Context:** It maintains a persistent browser profile. Once you log in, your session state (like cookies and local storage) is saved locally so you don't have to provide passwords or 2FA again.
- **Headless Re-authentication:** For all subsequent runs, the script runs in the background (headless mode) and automatically clicks through the account selector and consent prompts, making re-authentication completely invisible to the user.

### How it Works

1. **CLI Execution:** The script starts a subprocess running `hermes auth login --device-code --provider google-antigravity`.
2. **URL Capture:** It reads the standard output from the `hermes` process line-by-line, looking for the generated Google OAuth URL.
3. **Flow Determination:** It checks for the presence of a login state flag file.
    - **First Time Run:** If the flag doesn't exist, it launches a visible browser and navigates to the OAuth URL. It will wait up to 10 minutes for you to complete the login and for Hermes to receive the successful local redirect (`http://localhost` or `http://127.0.0.1`). Upon success, it writes a "logged-in" flag file.
    - **Automated Run:** If the flag exists, it launches headless Chromium with the persistent profile. The script automatically clicks the correct account and "Sign In" buttons, completing the entire OAuth flow on your behalf in seconds.
4. **Completion:** The browser closes gracefully once the local redirect signals that Hermes has successfully captured the authentication tokens.

### Data Storage & Paths

All persistent auth automation data is stored securely in your user's home directory:

- **Base Directory:** `~/.google-oauth-automation/`
- **Chrome Profile:** `~/.google-oauth-automation/chrome-profile/` (Contains cookies, session data)
- **State Flag:** `~/.google-oauth-automation/logged-in` (Its existence triggers headless mode)

### Usage Instructions

1. Ensure the proper dependencies are installed (refer to the local `requirements.txt`). Usually, this requires the playwright package and its browser binaries:
   ```bash
   pip install -r requirements.txt
   playwright install chromium
   ```

2. Run the automation script:
   ```bash
   python reauth.py
   ```

### Debugging & Troubleshooting

If you need to force the script to run with a visible browser (for instance, if you need to switch accounts, or if the headless automation is failing), you can run the script with the `DEBUG` environment variable:

```bash
DEBUG=1 python reauth.py
```

Setting `DEBUG` will safely bypass the headless flag and spawn a visible Chromium context.
