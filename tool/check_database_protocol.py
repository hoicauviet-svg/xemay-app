import json
import pathlib
import subprocess
import sys
root=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'database_helper'))
from bridge import target_uri, sql_connection
from unittest.mock import patch
from mssql_python.connection_string_parser import _ConnectionStringParser
from urllib.parse import parse_qs,urlsplit

assert parse_qs(urlsplit(target_uri('mongodb://u:p@host/XM','XM_copy')).query)['authSource']==['XM']
assert parse_qs(urlsplit(target_uri('mongodb://u:p@host/?authSource=admin','XM_copy')).query)['authSource']==['admin']
assert parse_qs(urlsplit(target_uri('mongodb+srv://u:p@host','XM_copy')).query)['authSource']==['admin']
captured={}
def connect_spy(connection, **kwargs):
    captured.update(connection=connection,kwargs=kwargs)
    return object()
with patch('mssql_python.connect',side_effect=connect_spy):
    sql_connection('Server=127.0.0.1,1433;Database=xm;UID=test;PWD={example;part}}end};Encrypt=yes;TrustServerCertificate=yes;Connect Timeout=12;')
_ConnectionStringParser(validate_keywords=True)._parse(captured['connection'])
assert captured['kwargs']['timeout']==12
assert 'APP=' not in captured['connection'] and 'Connection Timeout=' not in captured['connection']
helper=root/'assets/database_helper/xemay_database_helper'

def run(request):
    result=subprocess.run([str(helper)],input=json.dumps(request)+'\n',text=True,capture_output=True,timeout=35)
    messages=[json.loads(line) for line in result.stdout.splitlines()]
    return result,messages

result,messages=run({'command':'probeMongo','mongoUri':'mongodb://127.0.0.1:27017/XM'})
assert result.returncode==0 and messages[-1]['data']['connected'] is True
assert isinstance(messages[-1]['data']['installed'],bool)
result,messages=run({'command':'checkSqlDriver'})
assert result.returncode==0 and messages[-1]['data']['available'] is True, 'Packaged native SQL driver missing'
secret='NOT_A_REAL_SECRET_982341'
result,messages=run({'command':'probeSql','sqlConnection':f'Server=127.0.0.1,1;Database=xm;UID=test;PWD={secret};Encrypt=yes;TrustServerCertificate=yes;Connect Timeout=2;'})
assert result.returncode!=0 and messages[-1]['event']=='error'
assert messages[-1].get('code') not in ('ImportError','ModuleNotFoundError','ConnectionStringParseError'), 'Driver failed before network connection'
assert secret not in result.stdout and secret not in result.stderr
print('PASS: packaged helper MongoDB connection, installation detection, driver-compatible connection attributes, timeout argument, SQL failure handling, authentication URI preservation and credential redaction.')
