"""Run using a virtualenv with database_helper/requirements-build.txt installed."""
from pathlib import Path
import importlib.util
import os
import subprocess
import sys
import tempfile
import json
from ensure_database_helper import source_digest, STAMP

root = Path(__file__).resolve().parents[1]
work = Path(tempfile.mkdtemp(prefix='xemay-db-helper-build-'))
windows = sys.platform == 'win32'
# A Windows onefile build starts a child process and drops redirected stdin.
# The app talks to the helper through stdin, so Windows uses a folder build.
command = [
    sys.executable, '-m', 'PyInstaller', '--noconfirm', '--clean',
    '--onedir' if windows else '--onefile',
    '--name', 'xemay_database_helper_windows' if windows else 'xemay_database_helper',
    '--distpath', str(root / ('build/database_helper' if windows else 'assets/database_helper')),
    '--workpath', str(work / 'build'),
    '--specpath', str(work / 'spec'),
    '--paths', str(root / 'database_helper'),
    '--hidden-import', 'mssql_python',
    '--hidden-import', 'normalization',
    '--hidden-import', 'inventory_schema',
    '--hidden-import', 'sales_schema',
    '--hidden-import', 'sql_connection',
    '--hidden-import', 'diagnostics',
    '--hidden-import', 'cloud_sync',
]
for package in ['mssql_python', 'mssql_python_odbc', 'mssql_py_core', 'pymongo', 'bson', 'certifi']:
    command += ['--collect-all', package]
for package in ['mssql-python', 'mssql-python-odbc', 'mssql-python-rs']:
    command += ['--copy-metadata', package]

module = importlib.util.find_spec('mssql_python')
if module is None or not module.origin:
    raise SystemExit('Chưa cài mssql-python trong môi trường build.')
package_dir = Path(module.origin).parent
for binary in package_dir.rglob('*'):
    if binary.suffix.lower() not in {'.so', '.pyd', '.dll', '.dylib'}:
        continue
    if not (binary.name.startswith('ddbc_bindings') or binary.suffix.lower() == '.dll'):
        continue
    relative = binary.parent.relative_to(package_dir)
    destination = 'mssql_python' if relative == Path('.') else 'mssql_python/' + relative.as_posix()
    command += ['--add-binary', f'{binary}{os.pathsep}{destination}']

command += [str(root / 'database_helper/bridge.py')]
subprocess.run(command, cwd=root, check=True)
expected = (
    root / 'build/database_helper/xemay_database_helper_windows/xemay_database_helper_windows.exe'
    if windows else root / 'assets/database_helper/xemay_database_helper'
)
if not expected.is_file():
    raise SystemExit(f'Không thấy {expected}')

# Verify the executable, not just its source, before shipping the Flutter asset.
request = work / 'capabilities.json'
request.write_text('{"command":"capabilities"}', encoding='utf-8')
probe = subprocess.run([str(expected), str(request)], capture_output=True, timeout=60, check=True)
events = [json.loads(line) for line in probe.stdout.decode('utf-8').splitlines()]
info = next(event['data'] for event in events if event.get('event') == 'result')
if info.get('protocolVersion') != 3 or not {'compareCloud', 'syncCloud'}.issubset(info.get('commands', [])):
    raise SystemExit('Cong cu du lieu vua dong goi chua ho tro cloud.')
if not windows:
    STAMP.write_text(source_digest() + '\n', encoding='utf-8')
print('Packaged helper supports cloud comparison and merge.')
