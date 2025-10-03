# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Private Coffee Chat (☕ 개인 커피챗) is a Flask-based 1:1 meeting reservation system integrated with Google Calendar. Users can only access the system with an invite code, view real available time slots from Google Calendar, and admins manually approve meeting requests.

**Tech Stack**: Flask (Python), SQLite, Google Calendar API, Google Meet, Gmail SMTP

## Essential Commands

### Development
```bash
# Run development server (uses .env.dev, port from FLASK_PORT)
FLASK_ENV=development python app.py

# Run production server (uses .env.prod)
FLASK_ENV=production python app.py
```

### Environment Setup
- **Environment files**: `.env.dev` and `.env.prod` (not in repo, must create)
- **Required env vars**:
  - `FLASK_ENV`: `development` or `production`
  - `FLASK_PORT`: Server port (default 9999)
  - `REDIRECT_URI`: OAuth callback URL
  - `GMAIL_ADDRESS`: Sender email for notifications
  - `GMAIL_APP_PASSWORD`: Gmail app password for SMTP
  - `GMAIL_CC`: Optional CC recipient

### Google OAuth Setup
```bash
# Initial OAuth flow (generates token.json)
# 1. Visit /auth/google endpoint
# 2. Complete Google OAuth consent
# 3. token.json is created automatically

# Token refresh happens automatically when expired (uses refresh_access_token in app.py)
```

### Database Management
```bash
# DB initializes automatically on first run
# Creates user.db with tables: reservations, invite_codes

# Reset database (CAUTION: deletes all data)
rm user.db && python app.py
```

### Reminder System
```bash
# Send reminder emails (1 hour before meetings)
python reminder_email.py

# Typically run via cron job:
# */10 * * * * cd /path/to/project && python reminder_email.py
```

## Architecture

### Core Workflow
1. **Invite Code Verification** (`/invite`) → Session-based access control
2. **Calendar Display** (`/calendar`) → Fetches free/busy from Google Calendar API
3. **Reservation Submission** (`/submit`) → Stores in SQLite with 16 time slots
4. **Admin Approval** (`/admin`) → Creates Google Meet event + sends confirmation email
5. **Status Tracking** (`/status`) → Phone number-based reservation lookup

### Key Components

**app.py (main application)**
- Session management: 10-minute session lifetime for invite code verification
- Time slot calculation: 30-minute intervals, 10:00-18:00 KST only
- Dynamic slot storage: 16 date/time pairs per reservation (expandable)
- Environment-aware config: Auto-loads `.env.dev` or `.env.prod` based on `FLASK_ENV`

**google_auth.py**
- OAuth flow builder with environment-specific redirect URIs
- Scopes: `calendar.readonly`, `calendar.events`

**calendar_utils.py**
- `create_meet_event()`: Creates calendar event with Google Meet link
- Automatically patches event description with Meet link

**email_utils.py**
- `send_meet_email()`: Dual-mode email sender
  - User mode: Meeting confirmation with Meet link
  - Admin mode: New reservation notification to admin

**reminder_email.py**
- Standalone script for 1-hour-before meeting reminders
- Uses `reminder_sent` flag to prevent duplicate emails
- Checks for meetings between now+55min and now+65min (±5min tolerance)

### Database Schema

**reservations table**
- Basic info: `code`, `name`, `email`, `phone`, `purpose`
- 16 dynamic slots: `slot_1_date`, `slot_1_time`, `slot_1_status`, ... `slot_16_date`, `slot_16_time`, `slot_16_status`
- Status tracking: `approved_slot`, `reminder_sent`, `meet_link`
- Slot statuses: `pending` (default), `approved`, `rejected`

**invite_codes table**
- `code`: Invite code string
- `is_active`: Boolean flag (only one active code at a time)
- `created_at`: Timestamp

### Critical Patterns

**Token Refresh Flow**
- `refresh_access_token()` in app.py reads `client_id`/`client_secret` from `client_secret.json`
- Automatically refreshes when `creds.expired` is True
- Updates `token.json` with new access token

**Slot Status Logic** (app.py:439-458)
- If `approved_slot` exists → "승인됨"
- Else if all non-empty statuses are "rejected" → "거절됨"
- Else → "대기 중"

**Security Notes**
- Admin password hardcoded: `"billyiscute"` in `/admin-login`
- Session-based access control for calendar and status pages
- OAuth uses `OAUTHLIB_INSECURE_TRANSPORT=1` for HTTP (development only)

## File Structure Context

```
/
├── app.py                  # Main Flask application
├── google_auth.py          # OAuth flow configuration
├── calendar_utils.py       # Google Calendar/Meet integration
├── email_utils.py          # Email notification system
├── reminder_email.py       # Standalone reminder script
├── requirements.txt        # Python dependencies
├── templates/              # Jinja2 HTML templates
│   ├── admin.html         # Admin dashboard
│   ├── calendar.html      # Calendar view with slot selection
│   ├── reservation.html   # Reservation form
│   └── status.html        # Reservation status lookup
├── user.db                # SQLite database (auto-created)
├── token.json             # Google OAuth credentials (auto-created)
└── client_secret.json     # Google OAuth client config (must provide)
```

## Important Notes

- **Timezone**: All datetime operations use `Asia/Seoul` (KST)
- **Slot Limit**: Maximum 16 time slots per reservation (hardcoded, expandable)
- **Time Restrictions**: Only 10:00-18:00 slots allowed (configurable via `is_within_allowed_time()`)
- **Google Calendar**: Uses freebusy API to detect conflicts, not event list
- **Email Integration**: Gmail SMTP requires app password, not regular password
- **Production Deployment**: Uses gunicorn (in requirements.txt), metrics via Prometheus
