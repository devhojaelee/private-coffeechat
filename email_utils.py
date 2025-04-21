
import smtplib
from email.message import EmailMessage

def send_meet_email(to_email, name, slot_time, meet_link):
    msg = EmailMessage()
    msg["Subject"] = f"{name}님과의 Google Meet 미팅 안내"
    msg["From"] = "hojaelee.aws@gmail.com"
    msg["To"] = to_email
    msg["Cc"] = "hoje0711@naver.com"

    msg.set_content(f"""안녕하세요 {name}님,

요청하신 미팅이 다음 시간에 승인되었습니다:

🕒 시간: {slot_time}
🔗 Google Meet 링크: {meet_link}

감사합니다.
""")
    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
        server.login("hojaelee.aws@gmail.com", "ngfnsfgqetmfeurf")
        server.send_message(msg)
