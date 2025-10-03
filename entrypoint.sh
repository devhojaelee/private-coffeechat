#!/bin/bash

# Exit on error
set -e

echo "🚀 Starting Private Coffee Chat Container..."

# Cron 데몬 시작 (리마인더 이메일용)
echo "⏰ Starting cron daemon..."
cron

# 미팅 리마인더 cron 작업 설정 (10분마다)
echo "📧 Setting up reminder email cron job..."
echo "*/10 * * * * cd /app && /usr/local/bin/python /app/reminder_email.py >> /var/log/reminder.log 2>&1" > /etc/cron.d/reminder
chmod 0644 /etc/cron.d/reminder
crontab /etc/cron.d/reminder
touch /var/log/reminder.log

# 토큰 갱신은 app.py에서 자동 처리됨 (수동 실행: docker exec -it private-coffeechat python refresh_token.py)

# 데이터베이스 초기화 (없으면 생성)
echo "📊 Initializing database..."
python -c "from app import init_db; init_db()"

# Gunicorn으로 Flask 앱 실행
echo "🌐 Starting Flask app with Gunicorn on port ${FLASK_PORT:-9999}..."
exec gunicorn --bind 0.0.0.0:${FLASK_PORT:-9999} \
    --workers 4 \
    --timeout 120 \
    --access-logfile - \
    --error-logfile - \
    --log-level info \
    "app:app"
