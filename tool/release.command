#!/usr/bin/env bash
# Bấm đúp file này trong Finder để tăng số build, commit và đẩy nhánh main.
# GitHub Actions dựng bộ cài Windows rồi đăng bản phát hành.
set -euo pipefail

trap 'echo; echo "Nhan Enter de dong cua so."; read -r _' EXIT

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Khong phai git repo." >&2
  exit 1
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$branch" != "main" ]]; then
  echo "Chi chay tren nhanh main. Dang o $branch." >&2
  exit 1
fi

secrets="$(git status --porcelain | cut -c4- | grep -E '(^|/)\.env($|\.)|\.pem$|credentials\.json$|(^|/)test-results/' || true)"
if [[ -n "$secrets" ]]; then
  echo "Dung lai vi cac file sau co the chua bi mat:" >&2
  echo "$secrets" >&2
  exit 1
fi

git fetch origin main
counts="$(git rev-list --left-right --count origin/main...HEAD)"
behind="$(echo "$counts" | awk '{print $1}')"
ahead="$(echo "$counts" | awk '{print $2}')"
dirty="$(git status --porcelain)"

if [[ "$behind" != "0" && "$ahead" != "0" ]]; then
  echo "Nhanh main lech voi GitHub. Hop nhat thu cong roi chay lai." >&2
  exit 1
fi

if [[ "$ahead" != "0" && -z "$dirty" ]]; then
  git push origin HEAD
  echo "Da day commit san co. Khong tang phien ban lan nua."
  exit 0
fi

if [[ "$behind" != "0" ]]; then
  git pull --ff-only origin main
fi

python3 - <<'PY'
from pathlib import Path
import re

pubspec_path = Path("pubspec.yaml")
version_path = Path("lib/core/app_version.dart")
pubspec = pubspec_path.read_text(encoding="utf-8")
version_file = version_path.read_text(encoding="utf-8")
match = re.search(r"(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", pubspec)
if match is None:
    raise SystemExit("Khong doc duoc version trong pubspec.yaml.")
name, build = match.group(1), int(match.group(2))
name_line = f"static const name = '{name}';"
build_line = f"static const build = {build};"
if name_line not in version_file or build_line not in version_file:
    raise SystemExit("lib/core/app_version.dart khong khop pubspec.yaml.")
next_build = build + 1
pubspec_path.write_text(
    pubspec[: match.start()]
    + f"version: {name}+{next_build}"
    + pubspec[match.end() :],
    encoding="utf-8",
)
version_path.write_text(
    version_file.replace(build_line, f"static const build = {next_build};", 1),
    encoding="utf-8",
)
print(f"{name}+{build} {name}+{next_build}")
PY

label="$(python3 - <<'PY'
from pathlib import Path
import re
text = Path("pubspec.yaml").read_text(encoding="utf-8")
match = re.search(r"(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", text)
print(f"{match.group(1)}+{match.group(2)}")
PY
)"

git add -A
git commit -m "$(cat <<EOF
Release $label so shop PCs download the new installer.

EOF
)"
git push origin HEAD
echo "Da tang phien ban len $label va day len GitHub."
echo "Ban cai dang duoc dung: https://github.com/hoicauviet-svg/xemay-app/actions"
echo "Khi xong, may cua hang tai: https://github.com/hoicauviet-svg/xemay-app/releases/latest"
