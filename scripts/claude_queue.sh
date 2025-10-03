#!/bin/bash

# Claude Code 병렬 실행 큐 매니저
# 최대 2개씩 동시 실행, 완료되면 다음 작업 시작

MAX_PARALLEL=2
SESSION="coffeechat-parallel"
PROJECT_DIR="/Users/hojaelee/Desktop/python/private-coffeechat"

# 현재 실행 중인 Claude 프로세스 수 확인
get_running_count() {
    tmux list-panes -t $SESSION -F "#{pane_current_command}" 2>/dev/null | grep -c "claude" || echo 0
}

# 특정 창에서 Claude 실행
start_claude_in_window() {
    local WINDOW_INDEX=$1
    local ISSUE_ID=$2
    local ISSUE_TITLE=$3

    echo "🚀 Starting Claude in window $WINDOW_INDEX for $ISSUE_ID..."

    tmux send-keys -t $SESSION:$WINDOW_INDEX "claude 'Implement Linear issue $ISSUE_ID: $ISSUE_TITLE. Please read the issue details from Linear and complete the implementation.'" C-m
}

# 창에서 작업 완료 여부 확인
is_window_idle() {
    local WINDOW_INDEX=$1
    local CMD=$(tmux list-panes -t $SESSION:$WINDOW_INDEX -F "#{pane_current_command}" 2>/dev/null)

    # bash 또는 zsh이면 idle (claude 실행 중이 아님)
    if [[ "$CMD" == "bash" ]] || [[ "$CMD" == "zsh" ]]; then
        return 0  # idle
    else
        return 1  # busy
    fi
}

# 메인 함수
main() {
    if [ -z "$1" ]; then
        echo "❌ Usage: $0 <issue_data_file>"
        echo "Example: $0 /tmp/linear_issues.txt"
        exit 1
    fi

    ISSUE_FILE=$1

    if [ ! -f "$ISSUE_FILE" ]; then
        echo "❌ Issue file not found: $ISSUE_FILE"
        exit 1
    fi

    # Issue 데이터 읽기 (형식: WINDOW_INDEX|ISSUE_ID|ISSUE_TITLE)
    declare -a QUEUE
    while IFS='|' read -r WIN_IDX ISSUE_ID ISSUE_TITLE; do
        QUEUE+=("$WIN_IDX|$ISSUE_ID|$ISSUE_TITLE")
    done < "$ISSUE_FILE"

    TOTAL=${#QUEUE[@]}
    echo "📋 Total issues: $TOTAL"
    echo "⚙️  Max parallel: $MAX_PARALLEL"
    echo ""

    COMPLETED=0
    CURRENT_IDX=0

    # 처음 MAX_PARALLEL개 시작
    for i in $(seq 0 $((MAX_PARALLEL - 1))); do
        if [ $i -lt $TOTAL ]; then
            IFS='|' read -r WIN_IDX ISSUE_ID ISSUE_TITLE <<< "${QUEUE[$i]}"
            start_claude_in_window "$WIN_IDX" "$ISSUE_ID" "$ISSUE_TITLE"
            CURRENT_IDX=$((i + 1))
        fi
    done

    # 모니터링 루프
    while [ $COMPLETED -lt $TOTAL ]; do
        sleep 5  # 5초마다 체크

        # 각 창의 상태 확인
        for i in $(seq 0 $((CURRENT_IDX - 1))); do
            IFS='|' read -r WIN_IDX ISSUE_ID ISSUE_TITLE <<< "${QUEUE[$i]}"

            if is_window_idle "$WIN_IDX"; then
                # 이 창이 완료되었고 아직 처리 안 된 issue가 있으면
                if [ $CURRENT_IDX -lt $TOTAL ]; then
                    echo "✅ Window $WIN_IDX completed. Starting next issue..."

                    IFS='|' read -r NEXT_WIN NEXT_ID NEXT_TITLE <<< "${QUEUE[$CURRENT_IDX]}"
                    start_claude_in_window "$NEXT_WIN" "$NEXT_ID" "$NEXT_TITLE"
                    CURRENT_IDX=$((CURRENT_IDX + 1))
                fi

                COMPLETED=$((COMPLETED + 1))
            fi
        done

        RUNNING=$(get_running_count)
        echo "📊 Progress: $COMPLETED/$TOTAL completed, $RUNNING running..."
    done

    echo ""
    echo "🎉 All issues completed!"
}

main "$@"
