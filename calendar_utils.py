from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from datetime import datetime, timedelta
import os

def create_meet_event(token_path, calendar_id, summary, start_time, duration_minutes=30):
    # Check if token file exists
    if not os.path.exists(token_path):
        raise FileNotFoundError(
            f"❌ token.json not found at {token_path}\n"
            f"Please visit /auth/google to generate initial token"
        )

    creds = Credentials.from_authorized_user_file(token_path)

    # Check if token needs refresh
    if creds.expired and creds.refresh_token:
        from app import refresh_access_token
        creds = refresh_access_token(creds)

    service = build("calendar", "v3", credentials=creds)

    end_time = start_time + timedelta(minutes=duration_minutes)

    event = {
        "summary": summary,
        "start": {
            "dateTime": start_time.isoformat(),
            "timeZone": "Asia/Seoul",
        },
        "end": {
            "dateTime": end_time.isoformat(),
            "timeZone": "Asia/Seoul",
        },
        "conferenceData": {
            "createRequest": {
                "requestId": f"meet_{start_time.timestamp()}",
                "conferenceSolutionKey": {
                    "type": "hangoutsMeet"
                },
            }
        }
    }

    created_event = service.events().insert(
        calendarId=calendar_id,
        body=event,
        conferenceDataVersion=1
    ).execute()

    meet_link = None
    try:
        meet_link = created_event.get('conferenceData', {}).get('entryPoints', [{}])[0].get('uri')
    except Exception as e:
        print(f"⚠️ Meet 링크 가져오기 실패: {e}")

    # ✅ Meet 링크를 description에 추가
    if meet_link:
        service.events().patch(
            calendarId=calendar_id,
            eventId=created_event['id'],
            body={
                "description": f"🔗 Google Meet 링크: {meet_link}"
            }
        ).execute()

    return meet_link
