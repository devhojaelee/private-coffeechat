# Docker 배포 가이드

## 사전 준비

1. **필수 파일 확인**
   ```bash
   # 다음 파일들이 프로젝트 루트에 있어야 합니다:
   - .env.prod (또는 .env.dev)
   - client_secret.json (Google OAuth 클라이언트 시크릿)
   ```

2. **.env.prod 파일 예시**
   ```bash
   # Naver SMTP
   NAVER_ADDRESS=your-email@naver.com
   NAVER_APP_PASSWORD=your-app-password
   NAVER_CC=cc-email@naver.com

   # Google OAuth
   REDIRECT_URI=http://your-domain.com:9999/oauth2callback

   # Flask
   FLASK_ENV=production
   FLASK_PORT=9999
   ```

## Docker 이미지 빌드 및 실행

### 1. Docker 이미지 빌드
```bash
docker-compose build
```

### 2. 컨테이너 실행
```bash
docker-compose up -d
```

### 3. 컨테이너 상태 확인
```bash
docker-compose ps
```

### 4. 로그 확인
```bash
docker-compose logs -f
```

### 5. 컨테이너 중지
```bash
docker-compose down
```

## Google OAuth 인증 (최초 1회)

컨테이너를 실행한 후, Google Calendar API 사용을 위해 OAuth 인증이 필요합니다:

1. 브라우저에서 접속:
   ```
   http://localhost:9999/oauth/start
   ```

2. Google 로그인 및 권한 승인

3. `token.json` 파일이 자동 생성됨 (볼륨으로 호스트에 저장됨)

## 데이터 영속성

다음 파일들은 Docker 볼륨으로 마운트되어 호스트에 저장됩니다:
- `user.db` - SQLite 데이터베이스
- `token.json` - Google OAuth 토큰
- `client_secret.json` - Google OAuth 클라이언트 시크릿
- `.env.prod` - 환경 변수

## 포트 변경

포트를 변경하려면 `docker-compose.yml` 파일을 수정하세요:

```yaml
ports:
  - "8080:9999"  # 호스트:8080 -> 컨테이너:9999
```

## 프로덕션 배포 시 주의사항

1. **HTTPS 사용 권장**
   - Nginx 또는 Caddy 리버스 프록시 사용
   - SSL 인증서 설정

2. **환경 변수 보안**
   - `.env.prod` 파일을 `.gitignore`에 추가
   - 민감한 정보는 Docker Secrets 사용 권장

3. **데이터베이스 백업**
   ```bash
   # SQLite 백업
   docker exec private-coffeechat cp /app/user.db /app/user.db.backup
   docker cp private-coffeechat:/app/user.db.backup ./backup/
   ```

4. **로그 관리**
   - Docker 로그 로테이션 설정
   ```yaml
   logging:
     driver: "json-file"
     options:
       max-size: "10m"
       max-file: "3"
   ```

## 개발 환경에서 사용

개발 환경에서는 코드 변경 시 자동 재시작을 위해 볼륨 마운트를 추가할 수 있습니다:

```yaml
volumes:
  - .:/app  # 전체 소스 코드 마운트
  - ./user.db:/app/user.db
```

그리고 환경변수를 변경:
```yaml
environment:
  - FLASK_ENV=development
```

## 문제 해결

### 컨테이너가 시작되지 않는 경우
```bash
# 로그 확인
docker-compose logs

# 컨테이너 재시작
docker-compose restart
```

### 데이터베이스 초기화
```bash
# 컨테이너 중지
docker-compose down

# 데이터베이스 파일 삭제
rm user.db

# 컨테이너 재시작 (자동으로 DB 재생성됨)
docker-compose up -d
```

### 포트 충돌
```bash
# 9999 포트를 사용 중인 프로세스 확인
lsof -i :9999

# 또는 docker-compose.yml에서 포트 변경
```
