#!/usr/bin/env python3
"""
Token Refresh Script - Proactive Google OAuth token refresh

This script checks the expiration time of token.json and refreshes it
if it's expiring within 7 days. Run this via cron to keep token fresh.

Recommended cron schedule:
*/30 * * * * cd /path/to/project && python refresh_token.py
"""

import os
import json
from datetime import datetime, timedelta
from google.oauth2.credentials import Credentials
import requests

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TOKEN_PATH = os.path.join(BASE_DIR, "token.json")
CLIENT_SECRET_FILE = os.path.join(BASE_DIR, "client_secret.json")


def refresh_access_token(creds):
    """Refresh Google OAuth access token using refresh token"""
    # Read client credentials
    with open(CLIENT_SECRET_FILE, "r") as f:
        client_config = json.load(f)

    client_id = client_config["web"]["client_id"]
    client_secret = client_config["web"]["client_secret"]
    refresh_token = creds.refresh_token

    if not refresh_token:
        raise Exception("No refresh token available.")

    token_url = "https://oauth2.googleapis.com/token"
    payload = {
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token",
    }

    res = requests.post(token_url, data=payload)
    if res.status_code == 200:
        token_data = res.json()
        creds.token = token_data["access_token"]
        creds.expiry = datetime.utcnow() + timedelta(seconds=int(token_data["expires_in"]))

        # Save refreshed token
        with open(TOKEN_PATH, "w") as token_file:
            token_file.write(creds.to_json())

        print(f"✅ Token refreshed successfully. New expiry: {creds.expiry}")
        return creds
    else:
        raise Exception(f"Access Token Refresh Failed: {res.text}")


def check_and_refresh_token():
    """Check token expiry and refresh if needed"""
    # Check if token file exists
    if not os.path.exists(TOKEN_PATH):
        print(f"⚠️  token.json not found at {TOKEN_PATH}")
        print(f"   Please visit /auth/google to generate initial token")
        return

    # Load credentials
    try:
        creds = Credentials.from_authorized_user_file(TOKEN_PATH)
    except Exception as e:
        print(f"❌ Failed to load token: {e}")
        return

    # Check if refresh token exists
    if not creds.refresh_token:
        print(f"❌ No refresh token found. Please re-authenticate via /auth/google")
        return

    # Check expiry
    if not creds.expiry:
        print(f"⚠️  No expiry time found in token")
        return

    now = datetime.utcnow()
    time_until_expiry = creds.expiry - now

    # Refresh if expiring within 7 days or already expired
    if time_until_expiry.total_seconds() < (7 * 24 * 60 * 60):
        print(f"🔄 Token expiring soon ({creds.expiry}). Refreshing...")
        try:
            refresh_access_token(creds)
        except Exception as e:
            print(f"❌ Token refresh failed: {e}")
    else:
        days_remaining = time_until_expiry.days
        print(f"✅ Token is valid. Expires in {days_remaining} days ({creds.expiry})")


if __name__ == "__main__":
    check_and_refresh_token()
