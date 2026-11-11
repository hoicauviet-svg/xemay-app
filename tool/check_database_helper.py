"""Offline packaged-helper smoke checks, including extracted Windows assets."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile


def check(executable):
    executable = Path(executable).resolve()
    with tempfile.TemporaryDirectory(prefix='xemay-helper-check-') as temporary:
        folder = Path(temporary) / 'Kiểm tra dữ liệu có dấu'
        folder.mkdir()
        def run(payload, bom=False):
            request = folder / 'yêu cầu dữ liệu.json'
            request.write_text(json.dumps(payload), encoding='utf-8-sig' if bom else 'utf-8')
            result = subprocess.run(
                [str(executable), str(request)], cwd=executable.parent,
                capture_output=True, timeout=45,
                env={**os.environ, 'APPDATA': str(folder), 'HOME': str(folder), 'PYTHONIOENCODING': 'cp1252'},
            )
            events = [json.loads(line) for line in result.stdout.decode('utf-8').splitlines()]
            assert not request.exists(), 'Helper must delete the request file'
            assert len(events) == 1, 'Expected one structured response'
            return result.returncode, events[0]

        code, event = run({'command': 'capabilities'}, bom=True)
        assert code == 0 and event['event'] == 'result'
        assert event['data']['protocolVersion'] == 3
        assert {'probeSql', 'probeMongo', 'clone', 'compareCloud', 'syncCloud'}.issubset(event['data']['commands'])
        code, event = run({'command': 'checkSqlDriver'})
        assert code == 0 and event['data']['available'] is True, 'Native SQL driver failed to import'
        code, event = run({'command': 'probeSql', 'sqlConnection': ''})
        assert code == 1 and event['event'] == 'error'
        assert event['message'] == 'Nhập Server, User Id và Password trong chuỗi SQL Server.'
        diagnostic = Path(event['logFile'])
        assert diagnostic.is_file(), 'Helper must write its diagnostic log'
        entry = json.loads(diagnostic.read_text(encoding='utf-8').splitlines()[-1])
        assert entry['command'] == 'probeSql' and entry['error_type'] == 'ValueError'
        for command in ('compareCloud', 'syncCloud'):
            code, event = run({'command': command, 'sourceUri': 'http://invalid', 'targetUri': 'http://invalid'})
            assert code == 1 and event['event'] == 'error'
            assert event.get('code') == 'InvalidURI', f'{command}: not dispatched correctly'
    print('Packaged helper: SQL driver, cloud commands, Unicode/BOM requests and logs verified.')


def check_zip(path):
    with tempfile.TemporaryDirectory(prefix='xemay-windows-archive-') as temporary:
        directory = Path(temporary) / 'Ứng dụng quản lý cửa hàng'
        directory.mkdir()
        with zipfile.ZipFile(path) as archive:
            for name in archive.namelist():
                (directory / name).resolve().relative_to(directory.resolve())
            archive.extractall(directory)
        helper = directory / 'xemay_database_helper_windows.exe'
        assert helper.is_file(), 'Windows ZIP is missing its executable'
        assert helper.read_bytes()[:2] == b'MZ', 'Expected a Windows executable'
        check(helper)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('path')
    parser.add_argument('--zip', action='store_true', dest='archive')
    args = parser.parse_args()
    check_zip(args.path) if args.archive else check(args.path)
