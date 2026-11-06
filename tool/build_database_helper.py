"""Run using a virtualenv with database_helper/requirements-build.txt installed."""
from pathlib import Path
import subprocess
import sys
import tempfile
import importlib.util

root=Path(__file__).resolve().parents[1]
work=Path(tempfile.mkdtemp(prefix='xemay-db-helper-build-'))
command=[sys.executable,'-m','PyInstaller','--noconfirm','--clean','--onefile',
    '--name','xemay_database_helper','--distpath',str(root/'assets/database_helper'),
    '--workpath',str(work/'build'),'--specpath',str(work/'spec')]
for package in ['mssql_python','mssql_python_odbc','mssql_py_core','pymongo','bson','certifi']:
    command+=['--collect-all',package]
for package in ['mssql-python','mssql-python-odbc','mssql-python-rs']:
    command+=['--copy-metadata',package]
# Microsoft's native extension uses a nonstandard filename loaded dynamically.
# PyInstaller's module discovery does not collect it automatically.
module=importlib.util.find_spec('mssql_python')
for binary in Path(module.origin).parent.glob('ddbc_bindings.*.so'):
    command += ['--add-binary',str(binary)+':mssql_python']
command += [str(root/'database_helper/bridge.py')]
subprocess.run(command,cwd=root,check=True)
