# ☕ Private Coffee Chat

![Deploy Status](https://github.com/devhojaelee/private-coffeechat/actions/workflows/deploy.yml/badge.svg)

**Private Coffee Chat**는 초대받은 사람만 사용할 수 있는 1:1 커피챗 예약 시스템입니다.
Google Calendar와 연동되어 실제 비어 있는 시간만 보여주며, 관리자가 승인한 시간에만 미팅이 확정됩니다.

![Coffee Chat Screenshot](image.png)

## 🎯 주요 기능

### 사용자 기능
- 📧 **이메일 인증**: 초대 코드 입력 후 이메일로 6자리 인증 코드 발송
- 📅 **실시간 캘린더 연동**: Google Calendar API를 통해 실제 가능한 시간만 표시
- ⏰ **30분 단위 예약**: 10:00-18:00 사이 30분 단위로 최대 16개 슬롯 선택 가능
- 🔄 **예약 관리**: 예약 조회, 변경, 취소 (이메일로 전송된 관리 링크)
- 📨 **자동 알림**: 예약 확정, 1시간 전 리마인더 이메일 발송

### 관리자 기능
- 🎛️ **관리자 대시보드**: 예약 승인/거절, 월별 통계, 링크 관리
- 📊 **통계 뷰**: 승인 대기, 승인 완료, 취소된 예약 현황
- 🔗 **초대 링크 관리**: 생성, 활성화/비활성화, 삭제, 일괄 삭제
- 📝 **상세 정보 조회**: 예약자 정보, 주제, 취소 사유 등
- 🎥 **Google Meet 자동 생성**: 승인 시 자동으로 Meet 링크 생성 및 캘린더 등록

## 🏗️ 기술 스택

### Backend
- **Flask** - Python 웹 프레임워크
- **SQLite** - 경량 데이터베이스
- **Google Calendar API** - 일정 연동
- **Google Meet API** - 화상회의 링크 생성
- **Gunicorn** - WSGI HTTP 서버 (프로덕션)

### Frontend
- **Bootstrap 5** - 반응형 UI 프레임워크
- **FullCalendar** - 캘린더 UI
- **Vanilla JavaScript** - 클라이언트 로직

### Deployment
- **Docker & Docker Compose** - 컨테이너화
- **GitHub Actions** - CI/CD 자동 배포
- **Synology NAS** - 프로덕션 서버

## 📦 설치 및 실행

### 로컬 개발 환경

```bash
# 1. 저장소 클론
git clone https://github.com/devhojaelee/private-coffeechat.git
cd private-coffeechat

# 2. 가상환경 생성 및 활성화
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# 3. 의존성 설치
pip install -r requirements.txt

# 4. 환경변수 설정
cp .env.dev.example .env.dev
# .env.dev 파일 편집 (Gmail, Google OAuth 정보 입력)

# 5. Google OAuth 설정
# - Google Cloud Console에서 프로젝트 생성
# - Calendar API, Meet API 활성화
# - OAuth 2.0 클라이언트 ID 생성 (웹 애플리케이션)
# - client_secret.json 다운로드 후 프로젝트 루트에 배치

# 6. 개발 서버 실행
FLASK_ENV=development python app.py
```

서버가 실행되면 `http://localhost:9999`에서 접속 가능합니다.

### Docker로 실행

```bash
# 1. 환경변수 설정
cp .env.prod.example .env.prod
# .env.prod 파일 편집

# 2. Docker Compose 실행
docker-compose up -d

# 3. 로그 확인
docker-compose logs -f

# 4. 중지
docker-compose down
```

## 🔧 환경 변수

### .env.dev / .env.prod
```bash
# Flask 설정
FLASK_ENV=development          # development 또는 production
FLASK_PORT=9999               # 서버 포트

# Google OAuth
REDIRECT_URI=http://localhost:9999/oauth2callback

# 이메일 설정 (Naver SMTP)
NAVER_ADDRESS=your-email@naver.com
NAVER_PASSWORD=your-app-password
ADMIN_EMAIL=admin@example.com
```

### Google OAuth 설정
1. [Google Cloud Console](https://console.cloud.google.com/) 접속
2. 새 프로젝트 생성
3. API 및 서비스 → 라이브러리에서 활성화:
   - Google Calendar API
   - Google Meet API
4. OAuth 2.0 클라이언트 ID 생성:
   - 애플리케이션 유형: 웹 애플리케이션
   - 승인된 리디렉션 URI: `http://localhost:9999/oauth2callback`
5. `client_secret.json` 다운로드 후 프로젝트 루트에 배치

## 📂 프로젝트 구조

```
private-coffeechat/
├── app.py                    # 메인 Flask 애플리케이션
├── google_auth.py            # Google OAuth 플로우
├── calendar_utils.py         # Google Calendar/Meet 유틸
├── email_utils.py            # 이메일 발송 유틸
├── reminder_email.py         # 리마인더 이메일 스크립트 (cron)
├── requirements.txt          # Python 의존성
├── docker-compose.yml        # Docker Compose 설정
├── Dockerfile               # Docker 이미지 정의
├── entrypoint.sh            # Docker 엔트리포인트
├── .github/workflows/       # GitHub Actions CI/CD
│   ├── ci.yml              # 테스트 및 린팅
│   └── deploy.yml          # 자동 배포
├── templates/               # Jinja2 HTML 템플릿
│   ├── admin.html          # 관리자 대시보드
│   ├── admin_login.html    # 관리자 로그인
│   ├── book_calendar.html  # 캘린더 예약 UI
│   ├── booking_form.html   # 예약 정보 입력
│   ├── booking_success.html # 예약 완료 페이지
│   ├── manage_booking.html # 예약 관리 페이지
│   └── verify_email.html   # 이메일 인증
├── static/                  # 정적 파일
│   ├── css/
│   └── js/
└── scripts/                 # 자동화 스크립트
```

## 🚀 배포

### CI/CD 파이프라인

GitHub Actions를 통한 자동 배포:

1. **CI (지속적 통합)**:
   - Python 구문 검사
   - flake8/pylint 코드 품질 검사
   - pytest 테스트 실행 (있는 경우)

2. **CD (지속적 배포)**:
   - SSH를 통해 배포 서버 접속
   - `git pull origin main`
   - `docker-compose down`
   - `docker-compose build`
   - `docker-compose up -d`

### 배포 서버 설정 (Synology NAS)

**필요 사항**:
- Docker 패키지 설치
- Git 패키지 설치
- SSH 활성화 (포트 2222)

**GitHub Secrets 설정**:
```
SERVER_HOST: [서버 IP 주소]
SERVER_USER: [SSH 사용자명]
SSH_PRIVATE_KEY: [SSH 개인키 내용]
```

**서버 초기 설정**:
```bash
# 1. 프로젝트 디렉토리 생성
mkdir -p /volume1/docker/private-coffeechat
cd /volume1/docker/private-coffeechat

# 2. Git 저장소 클론
git clone https://github.com/devhojaelee/private-coffeechat.git .

# 3. 환경변수 파일 생성
nano .env.prod
# 필요한 환경변수 입력

# 4. Google OAuth 파일 배치
# client_secret.json, token.json 복사

# 5. 사용자를 docker 그룹에 추가
sudo synogroup --member docker [사용자명]

# 6. 수동 배포 테스트
docker-compose up -d
```

## 🔐 보안

- ✅ **초대 코드 시스템**: 관리자가 생성한 링크만 접근 가능
- ✅ **이메일 인증**: 6자리 OTP 인증 (5분 유효)
- ✅ **세션 관리**: 10분 자동 만료
- ✅ **관리자 인증**: 비밀번호 기반 로그인
- ✅ **취소 토큰**: UUID 기반 예약 관리 링크
- ✅ **Docker 그룹 권한**: sudo 없이 안전한 배포

## 📊 데이터베이스 스키마

### bookings 테이블
```sql
CREATE TABLE bookings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT NOT NULL,
    purpose TEXT NOT NULL,
    selected_slot TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    cancel_token TEXT UNIQUE,
    cancel_reason TEXT,
    meet_link TEXT,
    event_id TEXT,
    reminder_sent INTEGER DEFAULT 0,
    confirmed_at TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

### invite_codes 테이블
```sql
CREATE TABLE invite_codes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    is_active INTEGER DEFAULT 1,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

## 🎨 UI/UX 특징

- **커피 테마**: 따뜻한 브라운 컬러 스킴
- **반응형 디자인**: 모바일/태블릿/데스크톱 지원
- **직관적 네비게이션**: 4단계 예약 프로세스
- **실시간 피드백**: 예약 가능 여부 시각적 표시
- **이메일 템플릿**: 브랜딩 일관성 유지

## 📝 라이선스

이 프로젝트는 개인 용도로 제작되었습니다.

## 👤 개발자

**hojae lee** - [GitHub](https://github.com/devhojaelee)

## 🙏 기여

버그 리포트 및 기능 제안은 [Issues](https://github.com/devhojaelee/private-coffeechat/issues)에 등록해주세요.
