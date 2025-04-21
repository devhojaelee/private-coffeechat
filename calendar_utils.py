
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from datetime import datetime, timedelta

def create_meet_event(token_path, calendar_id, summary, start_time, duration_minutes=30):
    creds = Credentials.from_authorized_user_file(token_path)
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

    event = service.events().insert(
        calendarId=calendar_id,
        body=event,
        conferenceDataVersion=1
    ).execute()

    return event.get("hangoutLink")
