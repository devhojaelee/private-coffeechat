# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## 프로젝트 개요

Private Coffee Chat (☕ 개인 커피챗)은 Google Calendar와 연동된 Flask 기반 1:1 미팅 예약 시스템입니다. 초대 코드로만 접근 가능하며, Google Calendar의 실제 가능한 시간대를 확인하고, 관리자가 수동으로 미팅 요청을 승인합니다.

**Tech Stack**: Flask (Python), SQLite, Google Calendar API, Google Meet, Gmail SMTP

## 파일 구조

```
/
├── app.py                     # Main Flask application
├── google_auth.py             # OAuth flow configuration
├── calendar_utils.py          # Google Calendar/Meet integration
├── email_utils.py             # Email notification system
├── reminder_email.py          # Standalone reminder script
├── refresh_token.py           # OAuth token refresh utility
├── requirements.txt           # Python dependencies
├── docker-compose.yml         # Docker Compose configuration
├── Dockerfile                 # Docker image definition
├── entrypoint.sh              # Docker entrypoint script
├── user.db                    # SQLite database (auto-created)
├── token.json                 # Google OAuth credentials (auto-created)
├── client_secret.json         # Google OAuth client config (must provide)
├── .claude/                   # Claude Code workflow automation
│   ├── 1-issue_maker.md      # Linear issue creation guide
│   ├── 2-ttalkak.sh          # Automated Sub Issue implementation
│   ├── 3-integrate.sh        # Parent branch integration script
│   ├── 4-create-pr.sh        # Automated PR creation from Linear
│   ├── PRD.md                # Project requirements document
│   └── settings.local.json   # Local Claude Code settings
├── docs/                      # Documentation
│   └── CI_CD_GUIDE.md        # CI/CD deployment guide
├── scripts/                   # Utility scripts
│   ├── auto_merge.sh
│   ├── auto_parallel_dev.sh
│   ├── claude_queue.sh
│   ├── cleanup_parallel_dev.sh
│   ├── integrate_and_test.sh
│   ├── linear_tmux.sh
│   └── merge_features.sh
├── static/                    # Static assets
│   ├── css/
│   │   └── progress.css      # Progress indicator styles
│   └── js/
│       └── progress.js       # Progress indicator logic
├── templates/                 # Jinja2 HTML templates
│   ├── admin.html            # Admin dashboard
│   ├── admin_login.html      # Admin login page
│   ├── calendar.html         # Calendar view with slot selection
│   ├── book_calendar.html    # Booking calendar interface
│   ├── book.html             # Booking page
│   ├── booking_form.html     # Booking form
│   ├── booking_success.html  # Booking confirmation
│   ├── manage_booking.html   # Booking management page
│   ├── edit_info.html        # Edit booking information
│   ├── edit_success.html     # Edit confirmation
│   ├── status.html           # Reservation status lookup
│   ├── verify_email.html     # Email verification page
│   ├── waitlist.html         # Waitlist form
│   ├── waitlist_success.html # Waitlist confirmation
│   ├── error.html            # Error page
│   ├── invalid_code.html     # Invalid invite code page
│   ├── invalid_token.html    # Invalid token page
│   └── base.html             # Base template
└── .github/                   # GitHub Actions workflows
    └── workflows/
        ├── deploy.yml        # Production deployment
        ├── ci.yml            # Continuous integration
        └── integration.yml   # Integration tests
```

## 주요 구현 명령어

### 개발 서버 실행
```bash
# Development server (.env.dev 사용, FLASK_PORT 포트 사용)
FLASK_ENV=development python app.py

# Production server (.env.prod 사용)
FLASK_ENV=production python app.py
```

### 환경 설정
- **환경 파일**: `.env.dev` 및 `.env.prod` (레포에 없음, 직접 생성 필요)
- **필수 환경 변수**:
  - `FLASK_ENV`: `development` 또는 `production`
  - `FLASK_PORT`: 서버 포트 (기본값 9999)
  - `REDIRECT_URI`: OAuth 콜백 URL
  - `GMAIL_ADDRESS`: 알림 이메일 발송자 주소
  - `GMAIL_APP_PASSWORD`: Gmail 앱 비밀번호 (SMTP용)
  - `GMAIL_CC`: 선택적 참조 수신자

### Google OAuth 설정
```bash
# 초기 OAuth 플로우 (token.json 생성)
# 1. /auth/google 엔드포인트 방문
# 2. Google OAuth 동의 완료
# 3. token.json 자동 생성

# 토큰 갱신은 만료 시 자동 처리 (app.py의 refresh_access_token 사용)
```

### 데이터베이스 관리
```bash
# DB는 첫 실행 시 자동 초기화
# reservations, invite_codes 테이블 생성

# 데이터베이스 리셋 (예시 - 주의: 모든 데이터 삭제)
rm user.db && python app.py
```

### 리마인더 시스템
```bash
# 미팅 1시간 전 리마인더 이메일 발송
python reminder_email.py

# 일반적으로 cron job으로 실행 (예시):
# */10 * * * * cd /path/to/project && python reminder_email.py
```

### Docker 배포
```bash
# Docker Compose로 실행 (프로덕션)
docker-compose up -d

# 로그 확인
docker-compose logs -f

# 재배포 (코드 변경 시)
docker-compose down
docker-compose build --pull
docker-compose up -d

# 컨테이너 접속
docker-compose exec app bash
```

**배포 환경**:
- Synology NAS에서 Docker Compose로 실행
- GitHub Actions로 자동 배포 (main 브랜치 push 시)
- 환경 변수는 `.env.prod` 파일 사용

## 개발 원칙

### 1. 테스트 및 품질 관리
- **자동화 (ttalkak.sh)**: 기본 구현 및 간단한 검증
- **사용자 테스트**: 통합 후 직접 테스트 수행
  - 단위 테스트: `python -m pytest`
  - 통합 테스트: 수동 실행 및 검증
  - 엣지 케이스 및 실패 시나리오 확인
- 테스트 통과 후에만 push

### 2. Git Workflow

#### 자동화 워크플로우 (.claude 스크립트)
1. **2-ttalkak.sh**: Sub Issue 브랜치에서 자동 구현
   - Parent 브랜치 자동 생성 (예시): `feature/100P-123-email-verification`
   - Sub 브랜치 자동 생성 (예시): `feature/100P-124-email-send`
   - Sub 브랜치에서 **commit 및 push** (백업 및 공유)
   - Linear Lock 레이블로 병렬 작업 관리

2. **3-integrate.sh**: Parent 브랜치에 통합
   - Parent 브랜치를 main에서 rebase (최신 상태 반영)
   - Sub 브랜치들을 Parent 브랜치에 merge
   - 충돌 발생 시 Claude와 대화형으로 해결
   - 통합 완료 후 **사용자가 직접 테스트**

3. **4-create-pr.sh**: Linear 정보로 PR 자동 생성
   - Linear MCP로 Parent/Sub Issue 정보 조회
   - Claude Code가 PR body 자동 작성
   - gh pr create 실행으로 PR 생성

4. **사용자 작업**: 통합 테스트 후 PR 생성
   - 통합 테스트 수행 (pytest, 수동 테스트 등)
   - 테스트 통과 시 Parent 브랜치 push
   - `./4-create-pr.sh {Parent-Issue-ID}` 실행
   - PR merge → main 배포 (GitHub Actions → Synology)

#### Lock 정책 (병렬 작업 관리)
- **목적**: 동시 작업으로 인한 혼란 방지 및 순서 보장
- **작동 방식**:
  - 같은 파일 수정 시 Lock 레이블 획득 필요 (예시: `Lock: app.py`)
  - Lock 소유 중인 다른 Sub Issue 있으면 BLOCKED
  - Lock 해제 후 대기 중인 Sub Issue 시작
- **충돌 해결**: 시간차 충돌은 integrate.sh에서 Claude와 대화형으로 해결

#### 수동 작업 원칙
- **테스트를 통과하면 git commit 합니다**
- `git add` 할 때는 **구현하면서 변경한 파일만 추가**합니다
- **main/master 브랜치에 직접 작업 금지**

### 3. 문서화
- 중요한 개발 환경 변화가 있을 때는 **CLAUDE.md 파일을 업데이트**합니다
  - 스크립트 변경 (예: 새로운 배포 스크립트 추가)
  - 패키지 관리자 변경 (예: pip → poetry)
  - 데이터베이스 관리 방식 변경 (예: SQLite → PostgreSQL)
  - 환경 변수 추가/변경
  - 새로운 외부 서비스 통합
- **워크플로우 가이드**:
  - `.claude/1-issue_maker.md`: Linear 이슈 생성 및 자동화 워크플로우
  - `.claude/PRD.md`: 프로젝트 요구사항 문서
  - `docs/CI_CD_GUIDE.md`: CI/CD 배포 가이드

## 주요 아키텍처

### Core Workflow (신규 시스템)
1. **Waitlist Registration** (`/waitlist`) → Email verification → Admin approval
2. **Booking Link Access** (`/book/<token>`) → Token-based access to booking page
3. **Calendar Display** (`/book/<token>/calendar`) → Real-time availability from Google Calendar
4. **Booking Submission** → Single slot selection → Email verification
5. **Admin Confirmation** (`/admin`) → Creates Google Meet event + sends confirmation
6. **Booking Management** (`/manage/<cancel_token>`) → View/cancel/reschedule bookings

### Legacy Workflow (16-slot 시스템)
1. **Invite Code Verification** (`/invite`) → Session-based access control
2. **Calendar Display** (`/calendar`) → Fetches free/busy from Google Calendar API
3. **Reservation Submission** (`/submit`) → Stores in SQLite with 16 time slots
4. **Admin Approval** (`/admin`) → Creates Google Meet event + sends confirmation email
5. **Status Tracking** (`/status`) → Phone number-based reservation lookup

### 주요 컴포넌트

**app.py** (Main Flask application)
- 신규 시스템:
  - Waitlist 관리: 이메일 인증 + 관리자 승인
  - Booking link 생성 및 관리
  - 예약 관리: 조회/취소/변경 기능
- 레거시 시스템:
  - 세션 관리: 초대 코드 인증을 위한 10분 세션
  - 동적 슬롯 저장: 예약당 16개 날짜/시간 쌍
- 공통:
  - 시간대 계산: 30분 간격, KST 10:00-18:00만 허용
  - 환경 인식 설정: `FLASK_ENV`에 따라 `.env.dev` 또는 `.env.prod` 자동 로드

**google_auth.py**
- 환경별 redirect URI를 가진 OAuth 플로우 빌더
- 스코프: `calendar.readonly`, `calendar.events`

**calendar_utils.py**
- `create_meet_event()`: Google Meet 링크가 포함된 캘린더 이벤트 생성
  - `event_id` 반환 (취소/변경 시 사용)
- `delete_event()`: 캘린더 이벤트 삭제 (예약 취소 시)
- 이벤트 설명에 Meet 링크 자동 패치

**email_utils.py**
- `send_meet_email()`: 다중 모드 이메일 발송
  - 사용자 모드: Meet 링크가 포함된 미팅 확인
  - 관리자 모드: 새 예약 알림
  - 예약 관리 링크: `manage_url` 파라미터 지원
- `send_verification_email()`: 이메일 인증 코드 발송
- `send_waitlist_approval_email()`: 대기자 승인 알림

**reminder_email.py**
- 미팅 1시간 전 리마인더를 위한 독립 실행 스크립트
- `reminder_sent` 플래그로 중복 이메일 방지
- now+55분 ~ now+65분 사이의 미팅 확인 (±5분 허용)

**refresh_token.py**
- OAuth 토큰 갱신 유틸리티
- 만료된 토큰 자동 갱신

### Database Schema

**bookings table** (신규 예약 시스템)
- Basic info: `name`, `email`, `phone`, `purpose`
- Booking link: `booking_link_id` (FK to booking_links)
- Slot info: `selected_slot` (single selected time slot)
- Status: `status` (pending, confirmed, cancelled)
- Links: `meet_link`, `cancel_token` (unique)
- Cancellation: `cancel_reason`, `cancelled_at`
- Email verification: `email_verified` (0 or 1)
- Timestamps: `created_at`, `confirmed_at`

**booking_links table** (예약 링크 관리)
- Link info: `token` (unique), `name`, `created_by`
- Status: `used` (0 or 1), `active` (0 or 1)
- Timestamps: `created_at`, `first_accessed_at`, `expires_at`

**waitlist table** (대기자 명단)
- User info: `email` (unique), `phone`, `name`, `purpose`
- Status: `status` (pending, approved, rejected)
- Access: `access_token` (unique)
- Email verification: `email_verified` (0 or 1)
- Timestamps: `created_at`, `approved_at`

**email_verification table** (이메일 인증)
- Email info: `email`, `code`
- Verification: `verified` (0 or 1)
- Timestamps: `created_at`, `expires_at`

**reservations table** (레거시 - 16개 슬롯 시스템)
- Basic info: `name`, `email`, `phone`, `purpose`
- Waitlist: `waitlist_id` (FK to waitlist)
- 16 dynamic slots: `slot_1_date`, `slot_1_time`, `slot_1_status`, ... `slot_16_date`, `slot_16_time`, `slot_16_status`
- Status tracking: `approved_slot`, `reminder_sent`, `meet_link`
- Slot statuses: `pending`, `approved`, `rejected`

## 중요 참고사항

### 공통
- **Timezone**: 모든 datetime 연산은 `Asia/Seoul` (KST) 사용
- **Time Restrictions**: 10:00-18:00 슬롯만 허용 (`is_within_allowed_time()`로 설정)
- **Google Calendar**: freebusy API를 사용하여 충돌 감지 (이벤트 목록 아님)
- **Email Integration**: Gmail SMTP는 앱 비밀번호 필요 (일반 비밀번호 아님)
- **OAuth**: 토큰 갱신은 `refresh_access_token()` 함수로 자동 처리

### 신규 시스템
- **Waitlist System**: 이메일 인증 필수, 관리자 승인 후 예약 가능
- **Booking Links**: Token 기반 예약 링크, 만료 시간 설정 가능
- **Email Verification**: 6자리 인증 코드, 10분 만료
- **Booking Management**: Cancel token으로 예약 조회/취소/변경
- **Single Slot**: 1회 예약당 1개의 시간대만 선택 가능

### 레거시 시스템
- **Slot Limit**: 예약당 최대 16개 시간대 (하드코딩, 확장 가능)
- **Invite Code**: 세션 기반 접근 제어 (10분 세션)
- **Multi-slot Selection**: 한 번에 최대 16개 시간대 선택 가능
