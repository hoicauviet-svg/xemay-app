"""Local helper diagnostics without connection strings or request payloads."""
import json
import os
from pathlib import Path
import re
import sys
import traceback
from datetime import datetime, timezone
from logging import LogRecord, ERROR
from logging.handlers import RotatingFileHandler

from sql_connection import parse_connection


def log_path():
    if sys.platform == 'win32':
        base = Path(os.environ.get('APPDATA') or Path.home() / 'AppData' / 'Roaming')
        base = base / 'vn.cuahang.xemayApp'
    elif sys.platform == 'darwin':
        base = Path.home() / 'Library' / 'Application Support' / 'vn.cuahang.xemayApp'
    else:
        base = Path.home() / '.local' / 'share' / 'vn.cuahang.xemayApp'
    return base / 'logs' / 'database-helper.log'


def redact(text, request):
    secrets = []
    for key in ('sqlConnection', 'mongoUri'):
        raw = request.get(key)
        if isinstance(raw, str) and raw:
            secrets.append(raw)
    try:
        options = parse_connection(request.get('sqlConnection', ''))
        for key in ('password', 'pwd', 'user id', 'uid', 'user', 'username'):
            value = options.get(key)
            if value:
                secrets.extend((value, value.replace('}', '}}')))
    except ValueError:
        pass
    for secret in sorted(set(secrets), key=len, reverse=True):
        text = text.replace(secret, '[REDACTED]')
    # Also cover connection details introduced by native libraries.
    text = re.sub(r'(?i)(mongodb(?:\+srv)?://)[^\s/]*@', r'\1[REDACTED]@', text)
    text = re.sub(r'''(?i)\b(PWD|Password|UID|User\s+Id)\s*=\s*(\{(?:\}\}|[^}])*\}|"(?:""|[^"])*"|'(?:''|[^'])*'|[^;\r\n]*)''',
                  r'\1=[REDACTED]', text)
    text = re.sub(r"(?i)(login failed for user\s+)'[^']*'", r"\1'[REDACTED]'", text)
    return text


def record_error(error, request, path=None):
    """Include original driver errors even when hidden with `raise ... from None`."""
    try:
        path = Path(path) if path is not None else log_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        details = []
        current = error
        seen = set()
        while current is not None and id(current) not in seen:
            seen.add(id(current))
            details.extend(traceback.format_exception(type(current), current, current.__traceback__, chain=False))
            current = current.__cause__ or current.__context__
        command = request.get('command', 'unknown')
        if command not in ('probeSql', 'probeMongo', 'clone', 'checkSqlDriver'):
            command = 'unknown'
        entry = {
            'time': datetime.now(timezone.utc).isoformat(),
            'command': command,
            'platform': sys.platform,
            'python': sys.version.split()[0],
            'error_type': type(error).__name__,
            'details': redact(''.join(details), request),
        }
        handler = RotatingFileHandler(path, maxBytes=2 * 1024 * 1024, backupCount=2, encoding='utf-8')
        try:
            # Direct handling also works when third-party logging is disabled.
            handler.handle(LogRecord('database-helper', ERROR, '', 0,
                                     json.dumps(entry, ensure_ascii=True), (), None))
        finally:
            handler.close()
        return str(path)
    except Exception:
        # Logging must never replace the actual database error.
        return None
