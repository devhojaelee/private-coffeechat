import os
import smtplib
from email.message import EmailMessage

def send_meet_email(to_email, name, slot_time, meet_link, admin_notice=False):
    msg = EmailMessage()

    if admin_notice:
        msg["Subject"] = f"[알림] {name}님의 예약 요청 도착"
        msg.set_content(f"""📬 새로운 예약 요청이 도착했습니다!

예약자 이름: {name}
희망 시간대: {slot_time}

관리자 페이지에서 확인해주세요.
""")
    else:
        msg["Subject"] = f"{name}님과의 Google Meet 미팅 안내"
        msg.set_content(f"""안녕하세요 {name}님,

요청하신 미팅이 다음 시간에 승인되었습니다:

🕒 시간: {slot_time}
🔗 Google Meet 링크: {meet_link}

감사합니다.
""")

    msg["From"] = os.getenv("GMAIL_ADDRESS")
    msg["To"] = to_email
    msg["Cc"] = os.getenv("GMAIL_CC")

    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
        server.login(
            os.getenv("GMAIL_ADDRESS"),
            os.getenv("GMAIL_APP_PASSWORD")
        )
        server.send_message(msg)
