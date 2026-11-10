"""Check the packaged SQL error protocol without requiring a database server."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def check(executable):
    with tempfile.TemporaryDirectory(prefix='xemay-helper-check-') as folder:
        request = Path(folder) / 'request.json'
        request.write_text(json.dumps({'command': 'probeSql', 'sqlConnection': ''}), encoding='utf-8')
        result = subprocess.run(
            [str(Path(executable).resolve()), str(request)],
            cwd=Path(executable).resolve().parent,
            capture_output=True, timeout=30,
            env={**os.environ, 'APPDATA': folder},
        )
        events = [json.loads(line) for line in result.stdout.decode('utf-8').splitlines()]
        assert result.returncode == 1, 'SQL validation must return an error status'
        assert len(events) == 1, 'Helper must return one structured response'
        assert events[0]['event'] == 'error', 'Expected a structured SQL error'
        assert events[0]['message'] == 'Nhập Server, User Id và Password trong chuỗi SQL Server.'
        assert not request.exists(), 'Helper must delete the request file'
        diagnostic = Path(events[0]['logFile'])
        assert diagnostic.is_file(), 'Helper must write its diagnostic log'
        entry = json.loads(diagnostic.read_text(encoding='utf-8').splitlines()[-1])
        assert entry['command'] == 'probeSql'
        assert entry['error_type'] == 'ValueError'
    print('SQL error response verified')


if __name__ == '__main__':
    check(sys.argv[1])
