#!/bin/bash
set -e

# create-pr.sh - Linear 정보를 기반으로 PR 자동 생성
# Usage: ./create-pr.sh {Parent-Issue-ID}

PARENT_ISSUE_ID="$1"

if [ -z "$PARENT_ISSUE_ID" ]; then
    echo "❌ Error: Parent Issue ID가 필요합니다"
    echo "Usage: ./create-pr.sh {Parent-Issue-ID}"
    echo "예시: ./create-pr.sh 100P-123"
    exit 1
fi

# 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current)
echo "📋 현재 브랜치: $CURRENT_BRANCH"

# Parent 브랜치 형식 확인 (feature/100P-123-...)
if [[ ! "$CURRENT_BRANCH" =~ ^feature/${PARENT_ISSUE_ID}- ]]; then
    echo "⚠️  Warning: 현재 브랜치가 feature/${PARENT_ISSUE_ID}-로 시작하지 않습니다"
    echo "계속하시겠습니까? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "❌ PR 생성 취소"
        exit 1
    fi
fi

echo ""
echo "🤖 Claude Code를 호출하여 Linear 정보로 PR을 생성합니다..."
echo ""

# Claude Code에게 PR 생성 요청
claude --prompt "
Linear MCP를 사용하여 Parent Issue ID: ${PARENT_ISSUE_ID}의 정보를 읽어서 GitHub PR을 생성해줘.

**단계**:
1. Linear MCP로 Parent Issue ${PARENT_ISSUE_ID} 정보 조회
   - 제목, 설명 확인
2. Linear MCP로 해당 Parent의 Sub Issue들 조회
   - 각 Sub Issue의 ID, 제목, 체크리스트 확인
3. 아래 형식으로 PR 생성:

\`\`\`
gh pr create --base main --head ${CURRENT_BRANCH} \\
  --title \"[Parent Issue 제목]\" \\
  --body \"
## Summary
[Parent Issue 설명 또는 주요 구현 내용 요약]

## Implemented Features
[각 Sub Issue별로 구현한 내용 나열]

## Sub Issues
[Sub Issue들 리스트: #ID - 제목]

## Test Plan
- [ ] Python 구문 검사 통과
- [ ] 수동 테스트 완료
- [ ] 기능 동작 확인

## Notes
[추가 참고사항이 있다면]
\"
\`\`\`

**중요**:
- Linear에서 실제 정보를 읽어서 PR body를 채워넣어야 함
- gh pr create 명령어를 실행해서 실제로 PR 생성
- PR URL을 출력해줘
"

echo ""
echo "✅ PR 생성 스크립트 완료"
