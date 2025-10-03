from flask import Flask, request, jsonify, render_template, redirect, url_for, session
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from google_auth_oauthlib.flow import Flow
from datetime import datetime, timedelta
from dateutil import parser
from pytz import timezone
from prometheus_flask_exporter import PrometheusMetrics  # ✅ 추가
from dotenv import load_dotenv
import pytz
import os
import sqlite3
import json
import sys
from calendar_utils import create_meet_event
from email_utils import send_meet_email
from collections import defaultdict

# 임시로 http 허용
os.environ["OAUTHLIB_INSECURE_TRANSPORT"] = "1"
app = Flask(__name__)
metrics = PrometheusMetrics(app)  # ✅ 성능 측정 활성화
app.secret_key = "super_secret_key"
app.permanent_session_lifetime = timedelta(minutes=10)  # ✅ 10분간 유효
korea_tz = timezone("Asia/Seoul")
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "user.db")
TOKEN_PATH = os.path.join(BASE_DIR, "token.json")
CLIENT_SECRET_FILE = os.path.join(BASE_DIR, "client_secret.json")
SCOPES = [
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/calendar",
]

# FLASK_ENV에 따라 알맞은 .env 파일 자동 선택
flask_env = os.getenv("FLASK_ENV", "development")

if flask_env == "production":
    env_file = ".env.prod"
else:
    env_file = ".env.dev"

print(f"✅ Loading environment from: {env_file}")  # 확인용 로그

load_dotenv(dotenv_path=env_file)
# 이후에 google_auth import
from google_auth import build_flow


PORT = int(os.getenv("FLASK_PORT", 9999))
DEBUG = os.getenv("FLASK_ENV") == "development"

REDIRECT_URI = os.getenv("REDIRECT_URI", "http://hojaelee.com:9999/oauth2callback")


# 초대코드 시스템 제거됨 (waitlist 시스템으로 대체)


def is_within_allowed_time(dt):
    return 10 <= dt.hour < 18


def refresh_access_token(creds):
    import requests

    # ✅ client_id와 client_secret을 직접 client_secret.json 파일에서 읽어온다
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
        creds.expiry = datetime.now() + timedelta(seconds=int(token_data["expires_in"]))
        # ✅ 새로 갱신한 토큰 저장
        with open(TOKEN_PATH, "w") as token_file:
            token_file.write(creds.to_json())
        return creds
    else:
        raise Exception("Access Token Refresh Failed: " + res.text)


def get_available_time_slots(
    token_path=TOKEN_PATH, year=None, month=None, view="month"
):
    creds = Credentials.from_authorized_user_file(token_path)
    # ✅ 토큰이 만료됐으면 새로 갱신
    if creds.expired and creds.refresh_token:
        creds = refresh_access_token(creds)
    service = build("calendar", "v3", credentials=creds)

    tz = pytz.timezone("Asia/Seoul")
    now = datetime.now(tz)

    if view == "month":
        if year is None or month is None:
            year, month = now.year, now.month
        import calendar

        last_day = calendar.monthrange(year, month)[1]
        start_dt = tz.localize(datetime(year, month, 1, 0, 0, 0))
        end_dt = tz.localize(datetime(year, month, last_day, 23, 59, 59))
    else:
        start_dt = now - timedelta(days=now.weekday())
        start_dt = start_dt.replace(hour=0, minute=0, second=0, microsecond=0)
        end_dt = start_dt + timedelta(days=7)

    body = {
        "timeMin": start_dt.isoformat(),
        "timeMax": end_dt.isoformat(),
        "timeZone": "Asia/Seoul",
        "items": [{"id": "primary"}],
    }
    busy_times = service.freebusy().query(body=body).execute()
    busy_periods = busy_times["calendars"]["primary"]["busy"]

    grouped = defaultdict(list)
    current = start_dt

    # ✅ 먼저 슬롯 계산
    while current < end_dt:
        date_str = current.strftime("%Y-%m-%d")
        grouped[date_str]  # ✅ 날짜 키 생성 (중복 있어도 문제 없음)

        slot_end = current + timedelta(minutes=30)

        if is_within_allowed_time(current):
            overlap = any(
                current < parser.isoparse(b["end"]).astimezone(tz)
                and slot_end > parser.isoparse(b["start"]).astimezone(tz)
                for b in busy_periods
            )
            if not overlap:
                grouped[date_str].append(
                    {
                        "start": current.strftime("%Y-%m-%dT%H:%M:%S"),
                        "end": slot_end.strftime("%Y-%m-%dT%H:%M:%S"),
                        "title": "Available",
                    }
                )

        current = slot_end

    # ✅ 여기서 하루 단위로 key가 누락된 날짜 채우기
    date_cursor = start_dt
    while date_cursor < end_dt:
        date_str = date_cursor.strftime("%Y-%m-%d")
        grouped[date_str]  # defaultdict이므로 자동으로 [] 채워짐
        date_cursor += timedelta(days=1)

    # ✅ JSON 응답으로 넘기려면 dict로 변환 후
    return jsonify(dict(grouped))


def init_db():
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()

        # 이메일 인증 테이블
        c.execute(
            """
            CREATE TABLE IF NOT EXISTS email_verification (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT,
                code TEXT,
                expires_at TEXT,
                created_at TEXT,
                verified INTEGER DEFAULT 0
            )
        """
        )

        # 🆕 예약 링크 테이블 (1회용, 익명 링크)
        c.execute(
            """
            CREATE TABLE IF NOT EXISTS booking_links (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                token TEXT UNIQUE NOT NULL,
                name TEXT,
                created_at TEXT,
                first_accessed_at TEXT,
                expires_at TEXT,
                used INTEGER DEFAULT 0,
                active INTEGER DEFAULT 1,
                created_by TEXT
            )
        """
        )

        # 🆕 예약 테이블 (통합)
        c.execute(
            """
            CREATE TABLE IF NOT EXISTS bookings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                booking_link_id INTEGER,
                name TEXT NOT NULL,
                email TEXT NOT NULL,
                phone TEXT,
                purpose TEXT,
                selected_slot TEXT,
                status TEXT DEFAULT 'pending',
                meet_link TEXT,
                cancel_token TEXT UNIQUE,
                created_at TEXT,
                confirmed_at TEXT,
                cancelled_at TEXT,
                email_verified INTEGER DEFAULT 0,
                FOREIGN KEY(booking_link_id) REFERENCES booking_links(id)
            )
        """
        )

        # 🔄 기존 테이블 유지 (하위 호환성)
        # Waitlist 테이블
        c.execute(
            """
            CREATE TABLE IF NOT EXISTS waitlist (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT UNIQUE,
                phone TEXT,
                name TEXT,
                purpose TEXT,
                status TEXT DEFAULT 'pending',
                access_token TEXT UNIQUE,
                created_at TEXT,
                approved_at TEXT,
                email_verified INTEGER DEFAULT 0
            )
        """
        )

        c.execute(
            """
            CREATE TABLE IF NOT EXISTS reservations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                waitlist_id INTEGER,
                name TEXT,
                email TEXT,
                phone TEXT,
                purpose TEXT,
        """
            + ",\n                ".join(
                [f"slot_{i}_date TEXT, slot_{i}_time TEXT" for i in range(1, 17)]
            )
            + ",\n"
            + """
                created_at TEXT,
                approved_slot TEXT,
        """
            + ",\n                ".join(
                [f"slot_{i}_status TEXT DEFAULT 'pending'" for i in range(1, 17)]
            )
            + """,
                reminder_sent INTEGER DEFAULT 0,
                meet_link TEXT,
                FOREIGN KEY(waitlist_id) REFERENCES waitlist(id)
            )
        """
        )

        # ✅ 기존 DB에도 waitlist_id 추가
        try:
            c.execute("ALTER TABLE reservations ADD COLUMN waitlist_id INTEGER")
        except sqlite3.OperationalError:
            pass

        try:
            c.execute("ALTER TABLE reservations ADD COLUMN meet_link TEXT")
        except sqlite3.OperationalError:
            pass

        # Waitlist 테이블에 name, purpose, email_verified 컬럼 추가 (기존 DB 호환)
        try:
            c.execute("ALTER TABLE waitlist ADD COLUMN name TEXT")
        except sqlite3.OperationalError:
            pass

        try:
            c.execute("ALTER TABLE waitlist ADD COLUMN purpose TEXT")
        except sqlite3.OperationalError:
            pass

        try:
            c.execute("ALTER TABLE waitlist ADD COLUMN email_verified INTEGER DEFAULT 0")
        except sqlite3.OperationalError:
            pass

        conn.commit()


@app.route("/")
def home():
    """메인 페이지 = 관리자 로그인"""
    if session.get("admin_logged_in"):
        return redirect("/admin")
    return redirect("/admin-login")


@app.route("/book/<token>", methods=["GET", "POST"])
def book_with_link(token):
    """🆕 예약 링크로 접속 (1회용, 30분 타이머)"""
    # 링크 유효성 검증
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            """
            SELECT id, name, created_at, first_accessed_at, expires_at, used, active
            FROM booking_links
            WHERE token = ?
            """,
            (token,)
        )
        link = c.fetchone()

    if not link:
        return render_template("error.html", message="유효하지 않은 예약 링크입니다."), 404

    link_id, link_name, created_at, first_accessed_at, expires_at, used, active = link

    # 활성화 여부 확인
    if not active:
        return render_template("error.html", message="이 예약 링크는 비활성화되었습니다."), 403

    # 사용 완료 확인
    if used:
        return render_template("error.html", message="이미 사용된 링크입니다."), 403

    now = datetime.now()

    # 미접속 시 7일 제한 확인
    created_dt = datetime.fromisoformat(created_at)
    if not first_accessed_at and (now - created_dt).days > 7:
        return render_template("error.html", message="링크가 만료되었습니다. (7일 경과)"), 403

    # 첫 접속 시 타이머 시작
    if not first_accessed_at:
        expires_dt = now + timedelta(minutes=30)
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute(
                "UPDATE booking_links SET first_accessed_at = ?, expires_at = ? WHERE id = ?",
                (now, expires_dt, link_id)
            )
            conn.commit()
    else:
        # 이미 접속한 적 있음 - 만료 확인
        if expires_at:
            expires_dt = datetime.fromisoformat(expires_at)
            if now > expires_dt:
                return render_template("error.html", message="링크가 만료되었습니다. (30분 경과)"), 403
        else:
            # expires_at이 None인 경우 (비정상 상태)
            expires_dt = now + timedelta(minutes=30)

    # GET: 예약 폼 표시
    if request.method == "GET":
        return render_template("book.html",
                             token=token,
                             link_name=link_name,
                             expires_at=expires_dt.isoformat())

    # POST: 예약 정보 제출
    import re

    name = request.form.get("name", "").strip()
    email = request.form.get("email", "").strip()
    phone = request.form.get("phone", "").strip()
    purpose = request.form.get("purpose", "").strip()

    # 유효성 검사
    name_regex = re.compile(r"^[가-힣a-zA-Z\s]+$")
    email_regex = re.compile(r"^[\w\.-]+@[\w\.-]+\.\w+$")
    phone_regex = re.compile(r"^[0-9/\-]+$")

    if not name or not name_regex.match(name):
        return render_template("book.html", token=token, link_name=link_name, error="이름은 한글, 영어, 띄어쓰기만 입력 가능합니다.")
    if not email or not email_regex.match(email):
        return render_template("book.html", token=token, link_name=link_name, error="이메일 형식이 올바르지 않습니다.")
    if not phone or not phone_regex.match(phone):
        return render_template("book.html", token=token, link_name=link_name, error="전화번호는 숫자, - 만 사용할 수 있습니다.")
    if not purpose or len(purpose.strip()) < 1:
        return render_template("book.html", token=token, link_name=link_name, error="대화하고 싶은 주제를 입력해주세요.")

    # Rate Limiting: 같은 이메일로 24시간 내 1회만
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            """
            SELECT COUNT(*) FROM bookings
            WHERE email = ? AND created_at > datetime('now', '-1 day')
            """,
            (email,)
        )
        count = c.fetchone()[0]

        if count > 0:
            return render_template("book.html", token=token, link_name=link_name, error="이미 24시간 내에 예약하셨습니다.")

    # 세션에 임시 저장
    session["pending_booking"] = {
        "booking_link_id": link_id,
        "name": name,
        "email": email,
        "phone": phone,
        "purpose": purpose,
        "token": token,
        "link_name": link_name
    }

    # 이메일 인증 코드 발송
    from email_utils import generate_verification_code, send_verification_email

    code = generate_verification_code()
    expires_at = datetime.now() + timedelta(minutes=5)

    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            """
            INSERT INTO email_verification (email, code, expires_at, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (email, code, expires_at, datetime.now())
        )
        conn.commit()

    try:
        send_verification_email(email, code)
        print(f"✅ 인증 코드 이메일 발송 성공: {email}")
    except Exception as e:
        print(f"❌ 이메일 발송 실패: {e}")
        return render_template("book.html", token=token, link_name=link_name, error=f"이메일 발송에 실패했습니다: {str(e)}")

    return render_template("verify_email.html", email=email, action="book")


@app.route("/book/<token>/calendar", methods=["GET", "POST"])
def book_calendar(token):
    """🆕 예약 링크 - 캘린더 슬롯 선택"""
    # 인증된 세션인지 확인
    verified_booking = session.get("verified_booking")
    if not verified_booking or verified_booking.get("token") != token:
        return redirect(f"/book/{token}")

    # 링크 유효성 재확인
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            "SELECT id, name FROM booking_links WHERE token = ? AND active = 1",
            (token,)
        )
        link = c.fetchone()

    if not link:
        return render_template("error.html", message="유효하지 않은 예약 링크입니다."), 404

    link_id, link_name = link

    if request.method == "POST":
        # 슬롯 선택 처리
        selected_slot = request.form.get("selected_slot")

        if not selected_slot:
            return render_template("book_calendar.html",
                                   token=token,
                                   link_name=link_name,
                                   booking=verified_booking,
                                   error="시간을 선택해주세요.")

        # cancel_token 생성
        import uuid
        cancel_token = str(uuid.uuid4())

        # bookings 테이블에 저장 & 링크 사용 완료 마킹
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute(
                """
                INSERT INTO bookings
                (booking_link_id, name, email, phone, purpose, selected_slot, status, cancel_token, email_verified, created_at)
                VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, 1, ?)
                """,
                (link_id, verified_booking["name"], verified_booking["email"],
                 verified_booking["phone"], verified_booking["purpose"],
                 selected_slot, cancel_token, datetime.now())
            )

            # 🆕 링크 사용 완료 표시
            c.execute(
                "UPDATE booking_links SET used = 1 WHERE id = ?",
                (link_id,)
            )
            conn.commit()

        # 세션 정리
        session.pop("verified_booking", None)

        # 성공 페이지로 이동
        return render_template("booking_success.html",
                               email=verified_booking["email"],
                               selected_slot=selected_slot)

    # GET: 캘린더 표시 (만료 시각도 전달)
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT expires_at FROM booking_links WHERE id = ?", (link_id,))
        row = c.fetchone()
        expires_at = row[0] if row else None

    return render_template("book_calendar.html",
                           token=token,
                           link_name=link_name,
                           booking=verified_booking,
                           expires_at=expires_at)


@app.route("/auth/google")
def auth_google():
    flow = Flow.from_client_secrets_file(
        CLIENT_SECRET_FILE, scopes=SCOPES, redirect_uri=REDIRECT_URI
    )
    auth_url, _ = flow.authorization_url(
        prompt="consent", access_type="offline", include_granted_scopes="true"
    )
    return redirect(auth_url)


@app.route("/oauth2callback")
def oauth2callback():
    flow = Flow.from_client_secrets_file(
        CLIENT_SECRET_FILE, scopes=SCOPES, redirect_uri=REDIRECT_URI
    )
    flow.fetch_token(authorization_response=request.url)
    creds = flow.credentials
    with open(TOKEN_PATH, "w") as token_file:
        token_file.write(creds.to_json())
    return render_template("success.html")


@app.route("/api/available-slots", methods=["GET"])
def available_slots():
    year = request.args.get("year", type=int)
    month = request.args.get("month", type=int)
    view = request.args.get("view", default="month")

    try:
        slots = get_available_time_slots(year=year, month=month, view=view)
        return slots
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/admin-login", methods=["GET", "POST"])
def admin_login():
    if request.method == "POST":
        if request.form["password"] == "billyiscute":
            session["admin_logged_in"] = True
            return redirect("/admin")
        else:
            # 비밀번호 틀렸을 때도 메시지와 함께 다시 렌더링
            return render_template("admin_login.html", error="❌ 비밀번호가 올바르지 않습니다.")
    return render_template("admin_login.html")


@app.route("/admin-logout", methods=["POST"])
def admin_logout():
    session.pop("admin_logged_in", None)
    return redirect("/")


@app.route("/admin", methods=["GET", "POST"])
def admin():
    if not session.get("admin_logged_in"):
        return redirect("/admin-login")

    if request.method == "POST":
        # 🆕 예약 링크 생성 (익명 링크, 1회용)
        if "create_booking_link" in request.form:
            import uuid

            link_name = request.form.get("link_name", "").strip()

            if not link_name:
                # flash 대신 에러 처리 (나중에 구현)
                pass
            else:
                token = str(uuid.uuid4())[:8]  # 짧은 토큰

                with sqlite3.connect(DB_PATH) as conn:
                    c = conn.cursor()
                    c.execute(
                        """
                        INSERT INTO booking_links (token, name, created_at, created_by)
                        VALUES (?, ?, ?, ?)
                        """,
                        (token, link_name, datetime.now(), "admin")
                    )
                    conn.commit()

                # 링크는 생성만 하고 이메일 발송하지 않음 (관리자가 직접 공유)
                print(f"✅ 예약 링크 생성 성공: {token}")

        # 🆕 예약 링크 비활성화
        elif "deactivate_link_id" in request.form:
            link_id = int(request.form["deactivate_link_id"])

            with sqlite3.connect(DB_PATH) as conn:
                c = conn.cursor()
                c.execute("UPDATE booking_links SET active = 0 WHERE id = ?", (link_id,))
                conn.commit()

        # 🆕 예약 링크 활성화
        elif "activate_link_id" in request.form:
            link_id = int(request.form["activate_link_id"])

            with sqlite3.connect(DB_PATH) as conn:
                c = conn.cursor()
                c.execute("UPDATE booking_links SET active = 1 WHERE id = ?", (link_id,))
                conn.commit()

        # 🆕 예약 승인 처리
        elif "approve_booking_id" in request.form:
            booking_id = int(request.form["approve_booking_id"])

            with sqlite3.connect(DB_PATH) as conn:
                c = conn.cursor()
                c.execute(
                    """
                    SELECT name, email, selected_slot
                    FROM bookings
                    WHERE id = ?
                    """,
                    (booking_id,)
                )
                row = c.fetchone()

                if row:
                    name, email, selected_slot = row

                    # Google Meet 이벤트 생성
                    slot_dt = datetime.strptime(selected_slot, "%Y-%m-%d %H:%M")
                    meet_link = create_meet_event(
                        TOKEN_PATH,
                        "hojaelee.aws@gmail.com",
                        f"{name}님과의 미팅",
                        slot_dt,
                        30  # 30분
                    )

                    # bookings 업데이트
                    c.execute(
                        """
                        UPDATE bookings
                        SET status = 'confirmed', meet_link = ?, confirmed_at = ?
                        WHERE id = ?
                        """,
                        (meet_link, datetime.now(), booking_id)
                    )
                    conn.commit()

                    # 이메일 발송
                    send_meet_email(
                        email,
                        name,
                        selected_slot,
                        meet_link,
                        admin_notice=False
                    )

        # Waitlist 승인 처리
        elif "approve_waitlist_id" in request.form:
            import uuid
            waitlist_id = int(request.form["approve_waitlist_id"])

            with sqlite3.connect(DB_PATH) as conn:
                c = conn.cursor()

                # access_token 생성
                access_token = str(uuid.uuid4())

                c.execute(
                    """
                    UPDATE waitlist
                    SET status = 'approved', access_token = ?, approved_at = ?
                    WHERE id = ?
                    """,
                    (access_token, datetime.now(), waitlist_id)
                )

                # 이메일 정보 가져오기
                c.execute("SELECT email, phone FROM waitlist WHERE id = ?", (waitlist_id,))
                row = c.fetchone()
                email, phone = row[0], row[1]

                conn.commit()

            # 이메일 발송
            from email_utils import send_calendar_link_email
            calendar_link = f"{request.host_url}calendar/{access_token}"
            send_calendar_link_email(email, calendar_link)

        # Waitlist 거절 처리
        elif "reject_waitlist_id" in request.form:
            waitlist_id = int(request.form["reject_waitlist_id"])

            with sqlite3.connect(DB_PATH) as conn:
                c = conn.cursor()
                c.execute(
                    "UPDATE waitlist SET status = 'rejected' WHERE id = ?",
                    (waitlist_id,)
                )
                conn.commit()
        if "approve_id" in request.form:
            res_id = int(request.form["approve_id"])
            with sqlite3.connect(DB_PATH) as conn:
                c = conn.cursor()
                c.execute(
                    "SELECT name, email, "
                    + ", ".join([f"slot_{i}_date, slot_{i}_time" for i in range(1, 17)])
                    + " FROM reservations WHERE id = ?",
                    (res_id,),
                )
                row = c.fetchone()
                name, email = row[0], row[1]
                slots = [
                    (row[i], row[i + 1])
                    for i in range(2, len(row), 2)
                    if row[i] and row[i + 1]
                ]

                if slots:
                    dt_slots = [
                        datetime.strptime(f"{d} {t}", "%Y-%m-%d %H:%M")
                        for d, t in slots
                    ]
                    dt_slots.sort()
                    start_dt = dt_slots[0]
                    end_dt = slots[-1][1]  # 마지막 slot의 end time

                    duration_minutes = 30  # 기본 미팅 시간 30분

                    # ✅ 미팅 생성
                    meet_link = create_meet_event(
                        TOKEN_PATH,
                        "hojaelee.aws@gmail.com",
                        f"{name}님과의 미팅",
                        start_dt,
                        duration_minutes,
                    )

                    # ✅ 메일 보내기
                    send_meet_email(
                        email,
                        name,
                        f"{start_dt.strftime('%Y-%m-%d %H:%M')} ~ {(start_dt + timedelta(minutes=duration_minutes)).strftime('%H:%M')}",
                        meet_link,
                    )

                    # ✅ approved_slot 저장 + meet_link 저장
                    c.execute(
                        """
                        UPDATE reservations
                        SET approved_slot = ?, meet_link = ?
                        WHERE id = ?
                    """,
                        (start_dt.strftime("%Y-%m-%d %H:%M"), meet_link, res_id),
                    )

                    # 슬롯별 상태 업데이트
                    for i, (slot_date, slot_time) in enumerate(slots):
                        c.execute(
                            f"UPDATE reservations SET slot_{i+1}_status = 'approved' WHERE id = ?",
                            (res_id,),
                        )
                conn.commit()

        elif "reject_id" in request.form:
            res_id = int(request.form["reject_id"])
            with sqlite3.connect(DB_PATH) as conn:
                c = conn.cursor()
                for i in range(1, 17):
                    c.execute(
                        f"UPDATE reservations SET slot_{i}_status = 'rejected' WHERE id = ?",
                        (res_id,),
                    )
                c.execute(
                    "UPDATE reservations SET approved_slot = NULL WHERE id = ?",
                    (res_id,),
                )
                conn.commit()

        elif "remove_id" in request.form:
            delete_id = int(request.form["remove_id"])
            with sqlite3.connect(DB_PATH) as conn:
                c = conn.cursor()
                c.execute("DELETE FROM reservations WHERE id = ?", (delete_id,))
                conn.commit()

    # Waitlist 목록 가져오기
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            """
            SELECT id, name, email, phone, purpose, status, created_at, approved_at
            FROM waitlist
            ORDER BY created_at DESC
            """
        )
        waitlist_rows = c.fetchall()

    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        slot_fields = []
        for i in range(1, 17):
            slot_fields.append(f"slot_{i}_date")
            slot_fields.append(f"slot_{i}_time")

        fields = (
            ["id", "name", "email", "phone", "purpose"]
            + slot_fields
            + ["created_at", "approved_slot"]
        )
        c.execute(
            f"SELECT {', '.join(fields)} FROM reservations ORDER BY created_at DESC"
        )
        rows = c.fetchall()

        cleaned_rows = []
        for row in rows:
            meta = row[:5]
            slot_data = row[5:37]
            slots = []
            for i in range(0, 32, 2):
                date, time = slot_data[i], slot_data[i + 1]
                if date and time:
                    slots.append(f"{date} {time}")
            created_at = row[37]
            approved_slot = row[38]

            # ✅ 상태 판단 로직 추가
            c.execute(
                "SELECT "
                + ", ".join([f"slot_{i}_status" for i in range(1, 17)])
                + " FROM reservations WHERE id = ?",
                (row[0],),
            )
            status_row = c.fetchone()
            slot_statuses = [s for s in status_row if s]

            non_empty_statuses = [s for s in slot_statuses if s and s.strip() != ""]

            if approved_slot:
                status_label = "승인됨"
            elif non_empty_statuses and all(
                s == "rejected" for s in non_empty_statuses
            ):
                status_label = "거절됨"
            else:
                status_label = "대기 중"

            cleaned_rows.append(
                tuple(meta) + (slots,) + (created_at, approved_slot, status_label)
            )

    for row in cleaned_rows:
        print("🟦 예약 ID:", row[0], "| 상태:", row[-1])

    # 🆕 예약 링크 목록 가져오기
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            """
            SELECT id, token, name, created_at, first_accessed_at, expires_at, used, active
            FROM booking_links
            ORDER BY created_at DESC
            """
        )
        booking_links = c.fetchall()

    # 🆕 예약 목록 가져오기
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            """
            SELECT b.id, b.name, b.email, b.phone, b.purpose, b.selected_slot,
                   b.status, b.meet_link, b.created_at, bl.name as link_name
            FROM bookings b
            LEFT JOIN booking_links bl ON b.booking_link_id = bl.id
            ORDER BY b.created_at DESC
            """
        )
        bookings = c.fetchall()

    return render_template(
        "admin.html",
        reservations=cleaned_rows,
        waitlist=waitlist_rows,
        booking_links=booking_links,
        bookings=bookings,
        host_url=request.host_url,
        now=datetime.now().isoformat()
    )


@app.route("/waitlist/submit", methods=["POST"])
def waitlist_submit():
    import re

    name = request.form.get("name", "").strip()
    email = request.form.get("email", "").strip()
    phone = request.form.get("phone", "").strip()
    purpose = request.form.get("purpose", "").strip()

    # 유효성 검사
    name_regex = re.compile(r"^[가-힣a-zA-Z\s]+$")
    email_regex = re.compile(r"^[\w\.-]+@[\w\.-]+\.\w+$")
    phone_regex = re.compile(r"^[0-9/\-]+$")

    if not name or not name_regex.match(name):
        return render_template("waitlist.html", error="이름은 한글, 영어, 띄어쓰기만 입력 가능합니다.")
    if not email or not email_regex.match(email):
        return render_template("waitlist.html", error="이메일 형식이 올바르지 않습니다.")
    if not phone or not phone_regex.match(phone):
        return render_template("waitlist.html", error="전화번호는 숫자, - 만 사용할 수 있습니다.")
    if not purpose or len(purpose.strip()) < 1:
        return render_template("waitlist.html", error="대화하고 싶은 주제를 입력해주세요.")

    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()

        # 중복 체크
        c.execute("SELECT id, status FROM waitlist WHERE email = ?", (email,))
        existing = c.fetchone()

        if existing:
            if existing[1] == 'approved':
                return render_template("waitlist.html", error="이미 승인된 이메일입니다.")
            else:
                return render_template("waitlist.html", error="이미 대기 중인 이메일입니다.")

    # 세션에 임시 저장
    session["pending_registration"] = {
        "name": name,
        "email": email,
        "phone": phone,
        "purpose": purpose
    }

    # 인증 코드 생성 및 발송
    from email_utils import generate_verification_code, send_verification_email

    code = generate_verification_code()
    expires_at = datetime.now() + timedelta(minutes=5)

    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            """
            INSERT INTO email_verification (email, code, expires_at, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (email, code, expires_at, datetime.now())
        )
        conn.commit()

    try:
        send_verification_email(email, code)
        print(f"✅ 인증 코드 이메일 발송 성공: {email}")
    except Exception as e:
        print(f"❌ 이메일 발송 실패: {e}")
        return render_template("waitlist.html", error=f"이메일 발송에 실패했습니다: {str(e)}")

    return render_template("verify_email.html", email=email, action="register")


@app.route("/verify-email", methods=["POST"])
def verify_email():
    email = request.form.get("email")
    code = request.form.get("code", "").strip()
    action = request.form.get("action")  # 'register' or 'edit'

    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            """
            SELECT code, expires_at FROM email_verification
            WHERE email = ? AND verified = 0
            ORDER BY created_at DESC LIMIT 1
            """,
            (email,)
        )
        row = c.fetchone()

    if not row:
        return render_template("verify_email.html", email=email, action=action, error="인증 코드가 존재하지 않습니다.")

    stored_code, expires_at = row[0], row[1]

    # 만료 확인
    if datetime.now() > datetime.fromisoformat(expires_at):
        return render_template("verify_email.html", email=email, action=action, error="인증 코드가 만료되었습니다.")

    # 코드 확인
    if code != stored_code:
        return render_template("verify_email.html", email=email, action=action, error="인증 코드가 일치하지 않습니다.")

    # 인증 성공 처리
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            "UPDATE email_verification SET verified = 1 WHERE email = ? AND code = ?",
            (email, code)
        )
        conn.commit()

    if action == "register":
        # Waitlist 등록
        pending = session.get("pending_registration")
        if not pending:
            return redirect("/")

        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute(
                """
                INSERT INTO waitlist (name, email, phone, purpose, status, email_verified, created_at)
                VALUES (?, ?, ?, ?, 'pending', 1, ?)
                """,
                (pending["name"], pending["email"], pending["phone"], pending["purpose"], datetime.now())
            )
            conn.commit()

        session.pop("pending_registration", None)
        return render_template("waitlist_success.html", email=email)

    elif action == "book":
        # 🆕 예약 링크로 예약
        pending = session.get("pending_booking")
        if not pending:
            return redirect("/")

        # 이메일 인증 완료, 캘린더로 이동
        session["verified_booking"] = pending
        session.pop("pending_booking", None)

        return redirect(f"/book/{pending['token']}/calendar")

    elif action == "edit":
        # 수정 페이지로 이동
        session["verified_email"] = email
        return redirect(f"/edit-info/{email}")

    return redirect("/")


@app.route("/reservation", methods=["POST"])
def reservation():
    raw = request.form.get("selected_slots", "")
    selected_slots = raw.split(",") if raw else []

    return render_template(
        "reservation.html",
        selected_slots=selected_slots
    )


@app.route("/submit", methods=["POST"])
def submit():
    selected_slots = request.form.getlist("selected_slots")
    waitlist_id = session.get("waitlist_id")

    # Waitlist에서 정보 가져오기
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            "SELECT name, email, phone, purpose FROM waitlist WHERE id = ?",
            (waitlist_id,)
        )
        row = c.fetchone()

    if not row:
        return render_template("invalid_token.html")

    name, email, phone, purpose = row[0], row[1], row[2], row[3]

    # 유효성 검사
    if not selected_slots:
        return render_template(
            "reservation.html",
            selected_slots=selected_slots,
            error_msg="예약 시간대를 1개 이상 선택해주세요.",
        )

    # ✅ 슬롯 파싱
    slot_dates = [""] * 16
    slot_times = [""] * 16
    for i, slot in enumerate(selected_slots):
        if i < 16:
            try:
                # ✅ 타임존 포함된 ISO 포맷 문자열 처리
                dt = datetime.strptime(slot.strip(), "%Y-%m-%dT%H:%M:%S")
                dt = korea_tz.localize(dt)  # naive → aware로 만들어줌
                slot_dates[i] = dt.strftime("%Y-%m-%d")
                slot_times[i] = dt.strftime("%H:%M")
            except Exception as e:
                print(f"❌ 슬롯 파싱 실패: {slot} → {e}")

    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            f"""
            INSERT INTO reservations (
                waitlist_id, name, email, phone, purpose,
                {', '.join([f"slot_{i}_date" for i in range(1, 17)])},
                {', '.join([f"slot_{i}_time" for i in range(1, 17)])},
                created_at
            ) VALUES (
                ?, ?, ?, ?, ?,
                {', '.join(['?'] * 16)},
                {', '.join(['?'] * 16)},
                ?
            )
        """,
            (
                waitlist_id,
                name,
                email,
                phone,
                purpose,
                *slot_dates,
                *slot_times,
                datetime.now(),
            ),
        )
        res_id = c.lastrowid

        # 관리자에게 알림 메일 보내기
        from email_utils import send_meet_email

        send_meet_email(
            to_email=os.getenv("NAVER_ADDRESS"),
            name=name,
            slot_time=", ".join(selected_slots),
            meet_link="N/A",
            admin_notice=True,
        )

    return render_template(
        "submit_success.html",
        name=name,
        selected_slots=selected_slots,
        res_id=res_id,
        phone=phone,
    )


@app.route("/calendar/<token>")
def calendar_view(token):
    # 토큰 검증
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            "SELECT id, email, phone, status FROM waitlist WHERE access_token = ?",
            (token,)
        )
        row = c.fetchone()

    if not row or row[3] != 'approved':
        return render_template("invalid_token.html")

    # 세션에 waitlist 정보 저장
    session["waitlist_id"] = row[0]
    session["waitlist_email"] = row[1]
    session["waitlist_phone"] = row[2]

    return render_template("calendar.html", token=token)


@app.route("/status/<int:res_id>")
def status(res_id):
    # ✅ 전화번호 기반 조회일 경우엔 세션에 저장된 res_id만 확인
    if session.get("status_res_id") != res_id:
        return redirect("/")

    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()

        # 이름 확인
        c.execute("SELECT name FROM reservations WHERE id = ?", (res_id,))
        row = c.fetchone()
        if not row:
            return render_template("status.html", error="해당 예약 번호는 존재하지 않습니다.")
        name = row[0]

        # 슬롯 상태 확인
        statuses = []
        approved_slots = []
        for i in range(1, 17):
            c.execute(
                f"SELECT slot_{i}_date, slot_{i}_time, slot_{i}_status FROM reservations WHERE id = ?",
                (res_id,),
            )
            r = c.fetchone()
            if r and r[0] and r[1] and r[2]:
                statuses.append(r[2])
                if r[2] == "approved":
                    try:
                        dt = datetime.strptime(f"{r[0]} {r[1]}", "%Y-%m-%d %H:%M")
                        approved_slots.append(dt)
                    except Exception as e:
                        print(f"⚠️ 시간 파싱 실패: {r} → {e}")

    # 상태 메시지 결정
    if any(s == "approved" for s in statuses):
        approved_slots.sort()
        start_dt = approved_slots[0]
        end_dt = approved_slots[-1] + timedelta(minutes=30)
        status_msg = f"""
            ✅ 예약이 승인되었습니다!<br>
            승인된 시간: <strong>{start_dt.strftime('%Y-%m-%d %H:%M')} ~ {end_dt.strftime('%H:%M')}</strong>
        """
    elif all(s == "rejected" for s in statuses if s):
        status_msg = "❌ 예약이 거절되었습니다."
    else:
        status_msg = "⏳ 예약이 아직 승인되지 않았습니다. 대기 중입니다."

    return render_template(
        "status.html", name=name, res_id=res_id, status_msg=status_msg
    )


@app.route("/status", methods=["POST", "GET"])
def status_form():
    phone = request.form.get("phone")
    if not phone:
        return "<h2 class='text-danger text-center'>전화번호를 입력해주세요.</h2>"

    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT id FROM reservations WHERE phone = ?", (phone,))
        result = c.fetchone()

    if result:
        res_id = result[0]
        session["status_res_id"] = res_id  # ✅ 세션에 저장
        return redirect(url_for("status", res_id=res_id))  # ✅ 그대로 사용 가능
    else:
        return render_template("status.html", error="해당 전화번호로 등록된 예약이 없습니다.")


@app.route("/status-check", methods=["GET"])
def status_check_page():
    return render_template("status.html")


@app.route("/edit-info-request", methods=["POST"])
def edit_info_request():
    """정보 수정 요청 - 이메일 입력"""
    import re

    email = request.form.get("email", "").strip()
    email_regex = re.compile(r"^[\w\.-]+@[\w\.-]+\.\w+$")

    if not email or not email_regex.match(email):
        return render_template("waitlist.html", error="올바른 이메일을 입력해주세요.")

    # Waitlist에 존재하고 pending 상태인지 확인
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT id, status FROM waitlist WHERE email = ?", (email,))
        row = c.fetchone()

    if not row:
        return render_template("waitlist.html", error="해당 이메일로 등록된 정보가 없습니다.")

    if row[1] != 'pending':
        return render_template("waitlist.html", error="승인된 정보는 수정할 수 없습니다. 관리자에게 문의하세요.")

    # 인증 코드 생성 및 발송
    from email_utils import generate_verification_code, send_verification_email

    code = generate_verification_code()
    expires_at = datetime.now() + timedelta(minutes=5)

    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            """
            INSERT INTO email_verification (email, code, expires_at, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (email, code, expires_at, datetime.now())
        )
        conn.commit()

    try:
        send_verification_email(email, code)
        print(f"✅ 인증 코드 이메일 발송 성공: {email}")
    except Exception as e:
        print(f"❌ 이메일 발송 실패: {e}")
        return render_template("waitlist.html", error=f"이메일 발송에 실패했습니다: {str(e)}")

    return render_template("verify_email.html", email=email, action="edit")


@app.route("/edit-info/<email>", methods=["GET", "POST"])
def edit_info(email):
    """정보 수정 페이지"""
    # 인증된 이메일인지 확인
    if session.get("verified_email") != email:
        return redirect("/")

    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            "SELECT name, phone, purpose FROM waitlist WHERE email = ? AND status = 'pending'",
            (email,)
        )
        row = c.fetchone()

    if not row:
        return redirect("/")

    if request.method == "POST":
        import re

        name = request.form.get("name", "").strip()
        phone = request.form.get("phone", "").strip()
        purpose = request.form.get("purpose", "").strip()

        # 유효성 검사
        name_regex = re.compile(r"^[가-힣a-zA-Z\s]+$")
        phone_regex = re.compile(r"^[0-9/\-]+$")

        errors = []
        if not name or not name_regex.match(name):
            errors.append("이름은 한글, 영어, 띄어쓰기만 입력 가능합니다.")
        if not phone or not phone_regex.match(phone):
            errors.append("전화번호는 숫자, - 만 사용할 수 있습니다.")
        if not purpose or len(purpose.strip()) < 1:
            errors.append("대화하고 싶은 주제를 입력해주세요.")

        if errors:
            return render_template(
                "edit_info.html",
                email=email,
                name=name,
                phone=phone,
                purpose=purpose,
                error=" / ".join(errors)
            )

        # 업데이트
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute(
                """
                UPDATE waitlist
                SET name = ?, phone = ?, purpose = ?
                WHERE email = ? AND status = 'pending'
                """,
                (name, phone, purpose, email)
            )
            conn.commit()

        session.pop("verified_email", None)
        return render_template("edit_success.html", email=email)

    return render_template(
        "edit_info.html",
        email=email,
        name=row[0],
        phone=row[1],
        purpose=row[2]
    )


@app.template_filter("datetime")
def parse_datetime(value, format="%Y-%m-%dT%H:%M"):
    return datetime.strptime(value, format)


@app.template_filter("add_duration")
def add_duration(value, minutes):
    return (value + timedelta(minutes=minutes)).strftime("%H:%M")


if __name__ == "__main__":
    init_db()
    app.run(debug=DEBUG, host="0.0.0.0", port=PORT)
