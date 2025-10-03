# GitHub Actions CI/CD 가이드

Private Coffee Chat 프로젝트의 자동화된 CI/CD 시스템 사용 가이드입니다.

## 📋 목차

1. [개요](#개요)
2. [워크플로우 종류](#워크플로우-종류)
3. [사용 방법](#사용-방법)
4. [로컬 자동화](#로컬-자동화)
5. [환경 설정](#환경-설정)
6. [트러블슈팅](#트러블슈팅)

---

## 개요

이 프로젝트는 3가지 GitHub Actions 워크플로우를 제공합니다:

1. **CI (Continuous Integration)** - 자동 테스트 & 린트
2. **Integration & Merge** - 병합 자동화
3. **Deploy** - 배포 자동화

---

## 워크플로우 종류

### 1. CI - Tests and Lint

**파일**: `.github/workflows/ci.yml`

**트리거**:
- `main` 브랜치에 push
- `feature/**` 브랜치에 push
- `integration-*` 브랜치에 push
- Pull Request 생성

**동작**:
```yaml
1. Python 구문 검사 (py_compile)
2. 테스트 실행 (pytest)
3. 코드 린팅 (flake8, pylint)
4. 커버리지 리포트 생성
```

**자동 실행**: ✅ (push/PR 시 자동)

---

### 2. Integration & Merge

**파일**: `.github/workflows/integration.yml`

**트리거**:
- 수동 실행 (workflow_dispatch)

**입력 파라미터**:
- `parent_issue_id`: Linear 부모 이슈 ID (예: 100P-116)
- `auto_merge_to_main`: main 병합 자동화 여부 (true/false)

**동작**:
```yaml
1. 모든 feature 브랜치를 integration 브랜치로 병합
2. 통합 테스트 실행
3. (옵션) main 브랜치로 자동 병합
4. 릴리즈 태그 생성
```

**자동 실행**: ❌ (수동 실행)

---

### 3. Deploy to Production

**파일**: `.github/workflows/deploy.yml`

**트리거**:
- `main` 브랜치에 push
- 수동 실행 (workflow_dispatch)

**동작**:
```yaml
1. 배포 전 테스트 실행
2. 배포 알림 출력
3. (선택) 서버 배포 (SSH 등)
4. 배포 상태 알림
```

**자동 실행**: ✅ (main push 시 자동) / ❌ (수동도 가능)

---

## 사용 방법

### Case 1: 자동 CI 테스트 (자동 실행)

feature 브랜치에서 작업 후 push하면 자동으로 실행:

```bash
git add .
git commit -m "feat: 새로운 기능 추가"
git push origin feature/100P-118
```

→ GitHub Actions에서 자동으로 테스트 & 린트 실행 ✅

---

### Case 2: Integration 자동화 (수동 실행)

모든 feature 브랜치를 병합하고 싶을 때:

#### GitHub UI에서 실행:

1. GitHub 저장소 → **Actions** 탭 이동
2. 왼쪽에서 **"Integration & Merge"** 선택
3. 오른쪽 **"Run workflow"** 버튼 클릭
4. 입력값 설정:
   - `parent_issue_id`: `100P-116`
   - `auto_merge_to_main`: `false` (수동 승인) 또는 `true` (자동 병합)
5. **"Run workflow"** 클릭

#### 결과:

- ✅ `integration-100P-116` 브랜치 생성
- ✅ 모든 `feature/100P-*` 브랜치 병합
- ✅ 테스트 실행
- ⚠️ main 병합은 수동 승인 필요 (production environment)

---

### Case 3: Main 병합 자동화

Integration 테스트가 통과하고 main에 병합하고 싶을 때:

**옵션 A: GitHub Actions 재실행**

1. Actions → "Integration & Merge" → "Run workflow"
2. `auto_merge_to_main`: `true` 선택
3. Production 환경 승인 대기 → 승인 클릭

**옵션 B: 로컬 스크립트 사용**

```bash
./scripts/auto_merge.sh 100P-116
```

(로컬에서 확인 프롬프트 포함)

---

## 로컬 자동화

GitHub Actions 없이 로컬에서 자동화하려면:

### 완전 자동 병합 스크립트

**파일**: `scripts/auto_merge.sh`

**사용법**:

```bash
./scripts/auto_merge.sh 100P-116
```

**동작 순서**:

1. `./scripts/integrate_and_test.sh 100P-116` 실행
2. 테스트 실행 (`pytest`)
3. **확인 프롬프트**: "Continue? (y/N)"
4. `./scripts/merge_features.sh 100P-116` 실행

**장점**:
- ✅ GitHub Actions 없이 로컬에서 완전 자동화
- ✅ 중간에 확인 단계 포함 (안전)
- ✅ 테스트 실패 시 자동 중단

---

## 환경 설정

### GitHub Repository Secrets

배포 자동화를 위해 필요한 Secrets:

```yaml
# Settings → Secrets and variables → Actions → New repository secret

SERVER_HOST: 배포 서버 IP/도메인
SERVER_USER: SSH 사용자명
SSH_PRIVATE_KEY: SSH 개인키 (배포용)
```

### GitHub Environments

Production 환경 설정 (수동 승인 필요):

1. Settings → Environments → "New environment"
2. 이름: `production`
3. Deployment protection rules:
   - ✅ Required reviewers (승인자 지정)
   - ✅ Wait timer: 5 minutes (선택)

---

## 워크플로우 비교

| 항목 | CI | Integration | Deploy |
|------|-----|-------------|---------|
| **트리거** | 자동 (push/PR) | 수동 | 자동/수동 |
| **목적** | 코드 품질 검사 | 병합 자동화 | 배포 자동화 |
| **실행 시간** | ~2분 | ~5분 | ~3분 |
| **승인 필요** | ❌ | ✅ (main 병합 시) | ✅ (production) |
| **실패 시 영향** | PR 차단 | 병합 중단 | 배포 중단 |

---

## 트러블슈팅

### 문제 1: Integration 워크플로우가 feature 브랜치를 찾지 못함

**원인**: 브랜치 이름이 `feature/{PARENT_ID}-*` 패턴이 아님

**해결**:
```bash
# 브랜치 이름 확인
git branch -a | grep feature/

# 올바른 패턴: feature/100P-116-1, feature/100P-116-2
# 잘못된 패턴: feature/my-custom-name
```

---

### 문제 2: Production 환경 승인이 무한 대기

**원인**: GitHub Environment에 승인자가 지정되지 않음

**해결**:
1. Settings → Environments → production
2. Deployment protection rules → Required reviewers
3. 자신 또는 팀원 추가

---

### 문제 3: 테스트가 없어서 CI 실패

**원인**: pytest가 테스트 파일을 찾지 못함

**해결**: 이미 처리됨 ✅

```yaml
# CI 워크플로우는 테스트가 없어도 통과하도록 설정됨
if [ -d "tests" ] || ls test_*.py 2>/dev/null | grep -q .; then
  pytest
else
  echo "No tests found, skipping pytest"
fi
```

---

### 문제 4: 스크립트 실행 권한 오류

**원인**: 실행 권한 없음

**해결**:
```bash
chmod +x scripts/*.sh
git add scripts/
git commit -m "fix: Add execute permission to scripts"
git push
```

---

## 추천 워크플로우

### 시나리오 1: 일반 개발 (수동 병합)

```bash
# 1. Feature 브랜치 작업
git checkout -b feature/100P-118
# ... 코드 작성 ...
git add . && git commit -m "feat: ..." && git push

# 2. CI 자동 실행 확인 (GitHub Actions)

# 3. 모든 feature 완료 후 Integration 수동 실행
# GitHub → Actions → Integration & Merge → Run workflow
# auto_merge_to_main: false

# 4. Integration 테스트 통과 확인 후 수동 병합
./scripts/merge_features.sh 100P-116
git push origin main
```

---

### 시나리오 2: 완전 자동화 (로컬)

```bash
# Feature 브랜치들 모두 push 완료 후
./scripts/auto_merge.sh 100P-116

# 확인 프롬프트에서 y 입력
# → 자동으로 integration → test → merge → push
```

---

### 시나리오 3: GitHub Actions 완전 자동화

```bash
# 모든 feature push 완료 후
# GitHub → Actions → Integration & Merge → Run workflow
# auto_merge_to_main: true

# → Production 환경 승인 대기
# → 승인 클릭
# → 자동으로 main 병합 완료
```

---

## 요약

| 방법 | 자동화 수준 | 안전성 | 사용 시나리오 |
|------|-------------|--------|---------------|
| **수동 스크립트** | ⭐⭐☆☆☆ | ⭐⭐⭐⭐⭐ | 학습용, 첫 배포 |
| **로컬 auto_merge.sh** | ⭐⭐⭐⭐☆ | ⭐⭐⭐⭐☆ | 빠른 개발 사이클 |
| **GitHub Actions (수동)** | ⭐⭐⭐☆☆ | ⭐⭐⭐⭐⭐ | 팀 협업, 리뷰 필요 |
| **GitHub Actions (자동)** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐☆☆ | 신뢰할 수 있는 테스트 |

---

## 다음 단계

- [ ] 실제 테스트 파일 작성 (`tests/test_app.py`)
- [ ] 배포 스크립트 커스터마이징 (서버 환경에 맞게)
- [ ] Slack/Discord 알림 통합
- [ ] 롤백 자동화 추가
