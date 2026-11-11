#!/bin/bash
set -euo pipefail

cd -- "$(dirname -- "$0")"

pause_on_error() {
  local result=$?
  if (( result != 0 )); then
    printf '\nKhông chạy được ứng dụng. Xem lỗi ở phía trên.\n'
    if [[ -t 0 ]]; then
      read -r -p 'Nhấn Enter để đóng… ' || true
    fi
  fi
  exit "$result"
}
trap pause_on_error EXIT

if command -v flutter >/dev/null 2>&1; then
  flutter_bin="$(command -v flutter)"
elif [[ -x "$HOME/flutter/bin/flutter" ]]; then
  flutter_bin="$HOME/flutter/bin/flutter"
else
  printf 'Chưa tìm thấy Flutter. Hãy cài Flutter hoặc thêm flutter/bin vào PATH.\n' >&2
  exit 1
fi

python3 tool/ensure_database_helper.py

printf 'Đang chạy ứng dụng quản lý cửa hàng…\n'
"$flutter_bin" run -d macos "$@"
