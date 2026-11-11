"""Keep the local macOS helper in step with its Python source before Flutter runs."""
import hashlib
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
STAMP = ROOT / 'assets/database_helper/xemay_database_helper.source.sha256'


def source_digest():
    paths = sorted((ROOT / 'database_helper').glob('*.py')) + [
        ROOT / 'database_helper/requirements-build.txt',
        ROOT / 'tool/build_database_helper.py', Path(__file__).resolve(),
    ]
    digest = hashlib.sha256()
    for path in paths:
        digest.update(path.name.encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def main():
    executable = ROOT / 'assets/database_helper/xemay_database_helper'
    if executable.is_file() and STAMP.exists() and STAMP.read_text().strip() == source_digest():
        print('Cong cu du lieu da duoc cap nhat.')
        return
    print('Dang cap nhat cong cu du lieu cho ung dung...', flush=True)
    environment = ROOT / '.dart_tool/helper-build-venv'
    python = environment / 'bin/python'
    if not python.exists():
        subprocess.run([sys.executable, '-m', 'venv', str(environment)], check=True)
    subprocess.run([str(python), '-m', 'pip', 'install', '-r', str(ROOT / 'database_helper/requirements-build.txt')], check=True)
    subprocess.run([str(python), str(ROOT / 'tool/build_database_helper.py')], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
