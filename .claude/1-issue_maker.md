# Issue Maker - Linear 이슈 생성 가이드

## 태스크 생성 구조

### 기본 구조
- **task**: 구현할 기능의 최상위 단위
- **체크리스트**: 각 task 내에서 완료해야 할 세부 항목들
- **parent-sub issue 패턴**: 복잡한 기능을 parent와 여러 sub issue로 분리

### Parent-Sub Issue 패턴 규칙

1. **코드 겹침 원칙**
   - 작업하는 코드가 겹치는 것은 반드시 **parent-sub issue로 연결**합니다
   - 같은 parent 아래에 있는 **Sub issue는 병렬로 작업**하기 때문에 **코드가 겹치면 안 됩니다**

2. **예시**
   ```
   Parent Issue: 사용자 인증 시스템 구현
   ├── Sub Issue 1: 로그인 UI 컴포넌트 (templates/login.html만 수정)
   ├── Sub Issue 2: 회원가입 API (app.py 회원가입 로직만 수정)
   └── Sub Issue 3: 인증 미들웨어 (auth_middleware.py만 수정)
   ```

   ❌ **잘못된 예**: Sub Issue 1과 2가 모두 app.py를 수정하는 경우
   ✅ **올바른 예**: 각 Sub Issue가 다른 파일을 수정하거나, 같은 파일의 다른 영역을 수정

## 작업 단계

### 1. task.json 파일 작성
- 프로젝트 루트에 `task.json` 파일을 생성합니다
- 이미 파일이 있으면 **덮어씌웁니다**
- 모든 task와 체크리스트를 구조화하여 기록합니다
- **이 파일은 Linear 이슈 생성 시에만 사용됩니다 (일회성 입력)**
- **이슈 생성 후에는 Linear가 single source of truth입니다**

**task.json 구조 예시**:
```json
{
  "team": "100products",
  "project": "Coffeechat",
  "tasks": [
    {
      "title": "이메일 인증 시스템 구현",
      "type": "parent",
      "description": "사용자 이메일 인증 기능 전체 구현",
      "sub_issues": [
        {
          "title": "이메일 인증 코드 생성 및 발송",
          "description": "SMTP를 통한 인증 코드 이메일 발송 기능",
          "priority": 1,
          "files": ["email_utils.py"],
          "checklist": [
            "인증 코드 생성 함수 구현",
            "SMTP 이메일 발송 로직",
            "테스트 작성"
          ]
        },
        {
          "title": "인증 코드 검증 API",
          "description": "이메일 인증 코드 검증 엔드포인트",
          "priority": 2,
          "files": ["app.py"],
          "checklist": [
            "POST /verify-email 엔드포인트 구현",
            "세션 관리 로직",
            "테스트 작성"
          ]
        },
        {
          "title": "인증 UI 통합",
          "description": "이메일 인증 템플릿 및 프론트엔드",
          "priority": 3,
          "files": ["templates/verify_email.html", "static/css/verify.css"],
          "checklist": [
            "인증 이메일 템플릿 생성",
            "인증 성공/실패 페이지",
            "스타일링"
          ]
        }
      ]
    }
  ]
}
```

**필드 설명**:
- `team`: Linear team name
- `project`: Linear project name
- `title`: 이슈 제목
- `type`: parent (sub_issues 있으면 자동으로 parent)
- `description`: 이슈 상세 설명
- `priority`: 우선순위 (숫자가 낮을수록 높은 우선순위, ttalkak.sh 실행 순서)
- `files`: 수정할 파일 목록 (병렬 작업 충돌 방지)
- `checklist`: 체크리스트 항목들

### 2. 작업 원칙

#### 기능 단위로 Task 쪼개기
- 한 번에 구현할 수 있는 **최소 단위**로 task를 분리합니다
- 각 task는 **하나의 명확한 목표**를 가져야 합니다
- 예상 작업 시간이 **2-4시간을 넘지 않도록** 쪼갭니다

#### 코드 겹침 방지 및 Lock 전략

**원칙**: 같은 parent의 sub issue는 **다른 파일** 또는 **다른 함수**를 수정해야 합니다

**Lock의 역할**:
- **목적**: 동시 작업 방지 및 순서 보장 (충돌 완전 방지 아님)
- **자동 처리**: ttalkak.sh가 Linear Lock 레이블로 자동 관리
- **충돌 해결**: 시간차 충돌은 integrate.sh에서 해결

**시나리오별 처리 (예시)**:

1. **완전 독립적 (Lock 불필요)**
   ```
   Sub Issue 1: templates/login.html 수정
   Sub Issue 2: static/css/style.css 수정
   Sub Issue 3: email_utils.py 수정
   → 병렬 작업, Lock 없음
   ```

2. **같은 파일, 다른 영역 (Lock 필요)**
   ```
   Sub Issue 1: app.py 로그인 함수만 수정
   Sub Issue 2: app.py 회원가입 함수만 수정
   → Lock: app.py
   → Sub Issue 1 완료 후 → Sub Issue 2 시작
   ```

3. **같은 파일, 큰 수정 (통합 권장)**
   ```
   Sub Issue 1: app.py 대규모 리팩토링
   Sub Issue 2: app.py 새 기능 추가
   → 하나의 task로 통합하거나
   → Sequential parent-sub 구조로 분리
   ```

### 2. Linear Issue 자동 생성

task.json 작성 후, Claude에게 다음과 같이 요청:

```
@task.json 읽고 Linear MCP로 이슈 생성해줘.

- Team: 100products
- Project: Coffeechat
- Parent issue 먼저 생성 후 Sub issue 연결
- 각 Sub issue의 description에 files 목록 포함
- 우선순위는 순서대로 설정
```

Claude가 자동으로:
1. task.json 파싱
2. Parent issue 생성
3. Sub issue 생성 및 parent 연결
4. 체크리스트를 issue description에 포함
5. 생성된 issue ID 목록 반환

### 3. ttalkak.sh 실행 (자동 구현)

Linear 이슈 생성 완료 후, 자동으로 Sub Issue들을 병렬 구현:
```bash
cd .claude
./ttalkak.sh {Parent-Issue-ID}
```

예: `./ttalkak.sh 100P-123`

**자동 처리 내용 (예시)**:
- Parent 브랜치 생성: `feature/100P-123-email-verification`
- Sub 브랜치 생성 및 구현:
  - `feature/100P-124-email-send`
  - `feature/100P-125-email-verify`
  - `feature/100P-126-email-ui`
- 각 Sub 브랜치에서 **commit 및 push** (백업 및 공유)

### 4. integrate.sh 실행 (통합)

Sub Issue 구현 완료 후, Parent 브랜치에 통합:
```bash
cd .claude
./integrate.sh {Parent-Issue-ID}
```

예: `./integrate.sh 100P-123`

**자동 처리 내용**:
1. Parent 브랜치로 checkout
2. **Parent 브랜치를 main에서 rebase** (main 최신 상태 반영)
   - 충돌 시 Claude Code와 대화형으로 해결
3. Sub 브랜치들을 우선순위 순으로 merge
   - 충돌 시 Claude Code와 대화형으로 해결
4. 통합 완료

### 5. 통합 테스트 및 PR 생성

통합 완료 후 사용자가 직접:
```bash
# 1. 통합 테스트
python -m pytest
# 또는
FLASK_ENV=development python app.py

# 2. 테스트 통과 시 Push
git push origin feature/100P-123-email-verification

# 3. PR 자동 생성 (Linear 정보 기반)
cd .claude
./create-pr.sh 100P-123
```

**create-pr.sh 자동 처리**:
- Linear MCP로 Parent Issue 정보 조회 (제목, 설명)
- Linear MCP로 Sub Issue들 정보 조회 (ID, 제목)
- Claude Code가 정보를 바탕으로 PR body 자동 작성
- gh pr create 실행으로 PR 생성
- PR URL 출력

**수동 PR 생성 (예시)**:
```bash
gh pr create --base main --head feature/100P-123-email-verification \
  --title "이메일 인증 시스템 구현" \
  --body "
## Summary
- 인증 코드 발송 기능
- 코드 검증 API
- UI 통합

## Sub Issues
- #100P-124: 인증 코드 발송
- #100P-125: 코드 검증 API
- #100P-126: UI 통합

## Test Plan
- [x] pytest 통과
- [x] 수동 테스트 완료
"
```

**PR Merge**:
```bash
gh pr merge --squash  # 또는 웹에서 merge
# → main 배포 (GitHub Actions → Synology)
```

**PR의 이점**:
- 여러 Sub Issue의 커밋들을 하나의 단위로 그룹화
- 나중에 롤백 시 명확한 지점 제공 (`git revert PR#15`)
- 변경 이력 문서화 및 검색 용이

## 체크리스트

### 새로운 기능 구현 시
- [ ] 기능을 최소 단위로 쪼개기
- [ ] Parent-Sub 구조 확인 (코드 겹침 여부)
- [ ] 각 Sub Issue의 수정 파일 목록 작성
- [ ] task.json 파일 작성
- [ ] Claude에게 "@task.json 읽고 Linear MCP로 이슈 생성해줘" 요청
- [ ] 생성된 Parent Issue ID 확인
- [ ] `./ttalkak.sh {Parent-Issue-ID}` 실행 → Sub Issue 자동 구현
- [ ] `./integrate.sh {Parent-Issue-ID}` 실행 → Parent 브랜치에 통합
- [ ] 통합 테스트 수행 (pytest, 수동 테스트)
- [ ] 테스트 통과 시 Parent 브랜치 push
- [ ] `./create-pr.sh {Parent-Issue-ID}` 실행 → Linear 정보로 PR 자동 생성
- [ ] PR merge → main 배포

## 주의사항

- 🚨 **코드 겹침 최소화**: 같은 파일 수정이 필요하면 Lock으로 순서 보장
- 🚨 **task.json을 항상 최신 상태로 유지합니다**
- 🚨 **각 Sub Issue는 독립적으로 완료 가능해야 합니다**
- 🚨 **Lock은 혼란 방지용**: 충돌은 integrate.sh에서 해결되므로 과도한 걱정 불필요
- 🚨 **files 목록 명시**: task.json에 수정할 파일 목록을 정확히 작성 (Lock 자동 생성)
