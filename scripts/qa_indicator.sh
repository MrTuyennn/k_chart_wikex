#!/usr/bin/env bash
# QA/QC tool cho indicator trong k_chart_jk — chạy độc lập từ terminal,
# không phụ thuộc Claude/skill nào.
#
# Dùng sau khi thêm/sửa 1 indicator: kiểm tra riêng test của indicator đó
# (nếu truyền tên), rồi LUÔN chạy lại toàn bộ bộ test indicator để phát hiện
# có ảnh hưởng ngầm tới indicator khác không (rủi ro thật: các secondary
# indicator dùng chung 1 chain mixin KEntity -> ... -> MACDEntity, nối sai
# thứ tự/tên field có thể phá field của indicator khác mà test riêng của
# indicator mới không bắt được).
#
# Usage:
#   scripts/qa_indicator.sh                 # chỉ audit toàn bộ (coverage + regression)
#   scripts/qa_indicator.sh atr              # + chạy riêng test của ATR trước
#   scripts/qa_indicator.sh atr_indicator    # (đuôi _indicator tùy chọn, tự bỏ)
#   scripts/qa_indicator.sh --list           # liệt kê tên indicator hợp lệ để truyền vào
#   scripts/qa_indicator.sh --help           # in usage này

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
cd "$ROOT" || exit 1

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

list_indicators() {
  for f in lib/indicator/main/*.dart lib/indicator/secondary/*.dart; do
    group=$(echo "$f" | grep -oE 'main|secondary')
    base=$(basename "$f" .dart)
    printf '%-10s %s\n' "$group" "${base%_indicator}"
  done
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --list) list_indicators; exit 0 ;;
esac

TARGET="${1:-}"
TARGET="${TARGET%_indicator}"
TARGET="${TARGET%.dart}"

FAIL=0

echo "== 1. Coverage gap check =========================================="
MISSING=0
for f in lib/indicator/main/*.dart lib/indicator/secondary/*.dart; do
  base=$(basename "$f" .dart)
  group=$(echo "$f" | grep -oE 'main|secondary')
  if [ ! -f "test/indicator/$group/${base}_test.dart" ]; then
    echo "MISSING TEST: $f"
    MISSING=1
  fi
done
if [ "$MISSING" -eq 0 ]; then
  echo "OK — mọi indicator đều có file test tương ứng."
else
  FAIL=1
fi

if [ -n "$TARGET" ]; then
  echo
  echo "== 2. Test riêng cho '$TARGET' ====================================="
  TARGET_FILE=""
  for group in main secondary; do
    f="test/indicator/$group/${TARGET}_indicator_test.dart"
    [ -f "$f" ] && TARGET_FILE="$f"
  done
  if [ -z "$TARGET_FILE" ]; then
    echo "Không tìm thấy test file cho '$TARGET' (đã thử test/indicator/{main,secondary}/${TARGET}_indicator_test.dart)."
    echo "-> Chạy 'scripts/qa_indicator.sh --list' để xem tên hợp lệ, hoặc viết test trước (skill qa-indicator)."
    FAIL=1
  else
    echo "Chạy $TARGET_FILE ..."
    if ! flutter test "$TARGET_FILE"; then
      FAIL=1
    fi
  fi
fi

echo
echo "== 3. Regression — toàn bộ bộ test indicator (bắt buộc) ==========="
echo "Kiểm tra indicator vừa thêm/sửa có làm hỏng indicator KHÁC không."
if ! flutter test test/indicator/; then
  echo "!! Có test FAIL trong bộ indicator — xem skill qa-indicator (mục quy trình xử lý fail)."
  FAIL=1
fi

echo
echo "== 4. dart analyze =================================================="
if ! dart analyze; then
  FAIL=1
fi

echo
echo "====================================================================="
if [ "$FAIL" -eq 0 ]; then
  echo "QA PASS — test mới ổn, không phát hiện regression ở indicator khác, coverage đủ."
else
  echo "QA FAIL — xem log phía trên. Không coi là xong cho tới khi mục fail được xử lý."
fi
exit "$FAIL"
