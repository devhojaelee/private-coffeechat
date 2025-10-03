import os
import smtplib
import random
from email.message import EmailMessage

def send_calendar_link_email(to_email, calendar_link):
    msg = EmailMessage()
    msg["Subject"] = "☕ 커피챗 예약 승인 - 시간을 선택해주세요"
    msg["From"] = os.getenv("NAVER_ADDRESS")
    msg["To"] = to_email

    msg.set_content(f"""안녕하세요!

커피챗 대기 명단이 승인되었습니다.

아래 링크를 클릭하여 원하시는 시간대를 선택해주세요:
🔗 {calendar_link}

감사합니다.
""")

    with smtplib.SMTP_SSL("smtp.naver.com", 465) as server:
        server.login(
            os.getenv("NAVER_ADDRESS"),
            os.getenv("NAVER_APP_PASSWORD")
        )
        server.send_message(msg)

def generate_verification_code():
    """6자리 인증 코드 생성"""
    return ''.join([str(random.randint(0, 9)) for _ in range(6)])

def send_verification_email(to_email, code):
    """이메일 인증 코드 발송"""
    msg = EmailMessage()
    msg["Subject"] = "☕ 커피챗 이메일 인증 코드"
    msg["From"] = os.getenv("NAVER_ADDRESS")
    msg["To"] = to_email

    msg.set_content(f"""안녕하세요!

커피챗 이메일 인증 코드입니다:

🔐 인증 코드: {code}

이 코드는 5분간 유효합니다.
""")

    with smtplib.SMTP_SSL("smtp.naver.com", 465) as server:
        server.login(
            os.getenv("NAVER_ADDRESS"),
            os.getenv("NAVER_APP_PASSWORD")
        )
        server.send_message(msg)

def send_booking_link_email(to_email, link_name, booking_url):
    """예약 링크 이메일 발송"""
    msg = EmailMessage()
    msg["Subject"] = f"☕ 커피챗 예약 링크 - {link_name}"
    msg["From"] = os.getenv("NAVER_ADDRESS")
    msg["To"] = to_email

    msg.set_content(f"""안녕하세요!

커피챗 예약을 위한 링크를 보내드립니다.

📝 {link_name}

아래 링크를 클릭하면 예약을 진행하실 수 있습니다:
🔗 {booking_url}

⚠️ 주의사항:
- 링크를 클릭하지 않으면 7일간 유효합니다.
- 링크를 처음 클릭하는 순간부터 30분간만 예약이 가능합니다.
- 예약을 완료하면 링크는 자동으로 만료됩니다.

감사합니다.
""")

    with smtplib.SMTP_SSL("smtp.naver.com", 465) as server:
        server.login(
            os.getenv("NAVER_ADDRESS"),
            os.getenv("NAVER_APP_PASSWORD")
        )
        server.send_message(msg)


def send_meet_email(to_email, name, slot_time, meet_link, manage_url=None, admin_notice=False):
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

        email_body = f"""안녕하세요 {name}님,

요청하신 미팅이 다음 시간에 승인되었습니다:

🕒 시간: {slot_time}
🔗 Google Meet 링크: {meet_link}
"""

        if manage_url:
            email_body += f"""
📝 예약 관리:
예약을 확인하거나 변경/취소하려면 아래 링크를 이용하세요:
{manage_url}

⚠️ 주의: 예약 취소 시 복구가 불가능합니다.
"""

        email_body += "\n감사합니다.\n"
        msg.set_content(email_body)

    msg["From"] = os.getenv("NAVER_ADDRESS")
    msg["To"] = to_email
    msg["Cc"] = os.getenv("NAVER_CC")

    with smtplib.SMTP_SSL("smtp.naver.com", 465) as server:
        server.login(
            os.getenv("NAVER_ADDRESS"),
            os.getenv("NAVER_APP_PASSWORD")
        )
        server.send_message(msg)
