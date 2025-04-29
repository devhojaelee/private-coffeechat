import os
import sqlite3
import smtplib
from datetime import datetime, timedelta
from email.message import EmailMessage
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "user.db")

# .env 파일 로딩
flask_env = os.getenv("FLASK_ENV", "development")
env_file = ".env.prod" if flask_env == "production" else ".env.dev"
load_dotenv(dotenv_path=env_file)

def send_reminder_email(to_email, name, meet_time, meet_link):
    msg = EmailMessage()
    msg["Subject"] = f"[Reminder] {name}님, 곧 미팅이 시작됩니다!"
    msg["From"] = os.getenv("GMAIL_ADDRESS")
    msg["To"] = to_email

    msg.set_content(f"""안녕하세요 {name}님,

요청하신 미팅이 곧 시작됩니다!

🕒 시간: {meet_time}
🔗 Google Meet 링크: {meet_link}

""")

    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
        server.login(os.getenv("GMAIL_ADDRESS"), os.getenv("GMAIL_APP_PASSWORD"))
        server.send_message(msg)

def send_reminders():
    now = datetime.now()
    one_hour_later = now + timedelta(hours=1)

    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("""
            SELECT id, name, email, approved_slot, meet_link FROM reservations
            WHERE approved_slot IS NOT NULL AND reminder_sent IS NULL
        """)
        rows = c.fetchall()

        for row in rows:
            res_id, name, email, approved_slot, meet_link = row

            if not approved_slot:
                continue

            approved_dt = datetime.strptime(approved_slot, "%Y-%m-%d %H:%M")

            # 예약시간이 now + 55~65분 사이에 있는 경우 (±5분 오차 허용)
            if now + timedelta(minutes=55) <= approved_dt <= now + timedelta(minutes=65):
                # ✅ 메일 보낼 때 meet_link 포함
                send_reminder_email(email, name, approved_dt.strftime("%Y-%m-%d %H:%M"), meet_link)

                # ✅ reminder_sent 표시
                c.execute("UPDATE reservations SET reminder_sent = 1 WHERE id = ?", (res_id,))
                conn.commit()
                print(f"✅ {name}님 리마인더 메일 전송 완료.")

if __name__ == "__main__":
    send_reminders()
