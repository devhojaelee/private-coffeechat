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


def get_active_code():
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            "SELECT code FROM invite_codes WHERE is_active = 1 ORDER BY created_at DESC LIMIT 1"
        )
        row = c.fetchone()
        return row[0] if row else None


def set_active_code(new_code):
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        # 모든 기존 코드 비활성화
        c.execute("UPDATE invite_codes SET is_active = 0")

        # 코드가 이미 있으면 is_active만 1로
        c.execute("SELECT id FROM invite_codes WHERE code = ?", (new_code,))
        if c.fetchone():
            c.execute(
                "UPDATE invite_codes SET is_active = 1 WHERE code = ?", (new_code,)
            )
        else:
            c.execute(
                "INSERT INTO invite_codes (code, is_active, created_at) VALUES (?, 1, ?)",
                (new_code, datetime.now()),
            )
        conn.commit()


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

        c.execute(
            """
            CREATE TABLE IF NOT EXISTS reservations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT, 
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
                meet_link TEXT   -- ✅ 추가!!
            )
        """
        )

        # ✅ 기존 DB에도 meet_link 추가
        try:
            c.execute("ALTER TABLE reservations ADD COLUMN meet_link TEXT")
        except sqlite3.OperationalError:
            pass  # 이미 있으면 무시

        # 초대 코드 테이블
        c.execute(
            """
            CREATE TABLE IF NOT EXISTS invite_codes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT UNIQUE,
                is_active INTEGER DEFAULT 1,
                created_at TEXT
            )
        """
        )

        c.execute("SELECT COUNT(*) FROM invite_codes")
        if c.fetchone()[0] == 0:
            c.execute(
                """
                INSERT INTO invite_codes (code, is_active, created_at)
                VALUES (?, 1, ?)
            """,
                ("code2025", datetime.now()),
            )
        conn.commit()


@app.route("/")
def home():
    return render_template("index.html")


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

    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        slot_fields = []
        for i in range(1, 17):
            slot_fields.append(f"slot_{i}_date")
            slot_fields.append(f"slot_{i}_time")

        fields = (
            ["id", "code", "name", "email", "phone", "purpose"]
            + slot_fields
            + ["created_at", "approved_slot"]
        )
        c.execute(
            f"SELECT {', '.join(fields)} FROM reservations ORDER BY created_at DESC"
        )
        rows = c.fetchall()

        cleaned_rows = []
        for row in rows:
            meta = row[:6]
            slot_data = row[6:38]
            slots = []
            for i in range(0, 32, 2):
                date, time = slot_data[i], slot_data[i + 1]
                if date and time:
                    slots.append(f"{date} {time}")
            created_at = row[38]
            approved_slot = row[39]

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

    return render_template(
        "admin.html", reservations=cleaned_rows, active_code=get_active_code()
    )


@app.route("/invite", methods=["GET", "POST"])
def invite():
    if request.method == "POST":
        code = request.form.get("code")
        if code == get_active_code():
            session["invited"] = True  # ✅ 세션 설정
            return redirect(url_for("calendar_view"))
        return render_template("invalid_code.html")
    return render_template("calendar.html")


@app.route("/reservation", methods=["POST"])
def reservation():
    raw = request.form.get("selected_slots", "")
    selected_slots = raw.split(",") if raw else []
    return render_template("reservation.html", selected_slots=selected_slots)


@app.route("/submit", methods=["POST"])
def submit():
    name = request.form.get("name")
    email = request.form.get("email")
    phone = request.form.get("phone")
    purpose = request.form.get("purpose")
    selected_slots = request.form.getlist("selected_slots")
    session["invited"] = True  # ✅ 세션 추가
    # ✅ 서버 측 유효성 검사
    import re

    name_regex = re.compile(r"^[가-힣a-zA-Z\s]+$")
    phone_regex = re.compile(r"^[0-9/\-]+$")
    email_regex = re.compile(r"^[\w\.-]+@[\w\.-]+\.\w+$")

    errors = []
    if not name or not name_regex.match(name):
        errors.append("이름은 한글, 영어, 띄어쓰기만 입력 가능합니다.")
    if not email or not email_regex.match(email):
        errors.append("이메일 형식이 올바르지 않습니다.")
    if not phone or not phone_regex.match(phone):
        errors.append("전화번호는 숫자, - 만 사용할 수 있습니다.")
    if not purpose or len(purpose.strip()) < 1:
        errors.append("용건을 입력해주세요.")
    if not selected_slots:
        errors.append("예약 시간대를 1개 이상 선택해주세요.")

    if errors:
        return render_template(
            "reservation.html",
            selected_slots=selected_slots,
            error_msg=" / ".join(errors),
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
                code, name, email, phone, purpose,
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
                "code2025",
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

        # ✅ 여기 추가: 관리자인 너한테 알림 메일 보내기
        from email_utils import send_meet_email  # 만약 맨 위 import 안 되어 있으면 추가!

        send_meet_email(
            to_email=os.getenv("GMAIL_ADDRESS"),  # 너한테 보냄
            name=name,
            slot_time=", ".join(selected_slots),
            meet_link="N/A",
            admin_notice=True,  # 알림 메일 모드
        )

    return render_template(
        "submit_success.html",
        name=name,
        selected_slots=selected_slots,
        res_id=res_id,
        phone=phone,
    )


@app.route("/calendar")
def calendar_view():
    if not session.get("invited"):
        return redirect("/")  # 초대코드 페이지로 리디렉트
    return render_template("calendar.html")


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


@app.template_filter("datetime")
def parse_datetime(value, format="%Y-%m-%dT%H:%M"):
    return datetime.strptime(value, format)


@app.template_filter("add_duration")
def add_duration(value, minutes):
    return (value + timedelta(minutes=minutes)).strftime("%H:%M")


if __name__ == "__main__":
    init_db()
    set_active_code("code2025")
    app.run(debug=DEBUG, host="0.0.0.0", port=PORT)
