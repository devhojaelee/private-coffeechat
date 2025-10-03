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
    event_id = created_event.get('id')

    try:
        meet_link = created_event.get('conferenceData', {}).get('entryPoints', [{}])[0].get('uri')
    except Exception as e:
        print(f"⚠️ Meet 링크 가져오기 실패: {e}")

    # ✅ Meet 링크를 description에 추가
    if meet_link:
        service.events().patch(
            calendarId=calendar_id,
            eventId=event_id,
            body={
                "description": f"🔗 Google Meet 링크: {meet_link}"
            }
        ).execute()

    return meet_link, event_id


def delete_event(token_path, calendar_id, event_id):
    """
    Google Calendar 이벤트 삭제

    Args:
        token_path: OAuth token 파일 경로
        calendar_id: 캘린더 ID (일반적으로 'primary' 또는 이메일)
        event_id: 삭제할 이벤트 ID

    Returns:
        bool: 삭제 성공 여부
    """
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

    try:
        service.events().delete(
            calendarId=calendar_id,
            eventId=event_id
        ).execute()
        print(f"✅ 이벤트 삭제 성공: {event_id}")
        return True
    except Exception as e:
        print(f"❌ 이벤트 삭제 실패: {e}")
        return False
