# google_auth.py

import os
from google_auth_oauthlib.flow import Flow

# ✅ 플라스크 개발 환경용 (로컬 테스트용) - "https" 없어도 인증 가능하게
os.environ["OAUTHLIB_INSECURE_TRANSPORT"] = "1"

# ✅ 클라이언트 시크릿 파일
CLIENT_SECRETS_FILE = "client_secret.json"

# ✅ 구글 캘린더 접근 권한
SCOPES = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/calendar.events"
]

# ✅ REDIRECT_URI는 이미 app.py에서 load_dotenv() 했으니까 여기서는 getenv만 사용
REDIRECT_URI = os.getenv("REDIRECT_URI", "http://hojaelee.com:9999/oauth2callback")  # 기본값은 localhost로 안전하게

def build_flow():
    return Flow.from_client_secrets_file(
        CLIENT_SECRETS_FILE,
        scopes=SCOPES,
        redirect_uri=REDIRECT_URI
    )
