import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sql_connection import parse_connection, sql_connection


class SqlAuthenticationTests(unittest.TestCase):
    def connect(self, value):
        driver = SimpleNamespace(connect=Mock(return_value=object()))
        with patch.dict(sys.modules, mssql_python=driver):
            result = sql_connection(value)
        driver.connect.assert_called_once()
        self.assertIs(result, driver.connect.return_value)
        args, kwargs = driver.connect.call_args
        return parse_connection(args[0]), kwargs

    def test_windows_named_instance(self):
        options, kwargs = self.connect(r'server=.\SQLEXPRESS;Database=XM;Trusted_Connection=True;')
        self.assertEqual(options['server'], r'.\SQLEXPRESS')
        self.assertEqual(options['database'], 'XM')
        self.assertEqual(options['trusted_connection'], 'yes')
        self.assertEqual(options['applicationintent'], 'ReadOnly')
        self.assertEqual(options['encrypt'], 'yes')
        self.assertEqual(options['trustservercertificate'], 'no')
        self.assertNotIn('uid', options)
        self.assertNotIn('pwd', options)
        self.assertEqual(kwargs['timeout'], 15)

    def test_windows_aliases(self):
        for flag in ('Trusted_Connection=yes', 'trusted_connection=1',
                     'Integrated Security=SSPI', 'Integrated Security=true'):
            with self.subTest(flag=flag):
                options, _ = self.connect('Server=local;Database=xm;' + flag)
                self.assertEqual(options['trusted_connection'], 'yes')

    def test_sql_auth_preserves_escaped_password(self):
        for flag in ('', 'Trusted_Connection=False;', 'Integrated Security=no;'):
            with self.subTest(flag=flag):
                options, _ = self.connect('Server=local;Database=xm;UID=u;PWD={p;ass}}word};' + flag)
                self.assertEqual(options['uid'], 'u')
                self.assertEqual(options['pwd'], 'p;ass}word')
                self.assertNotIn('trusted_connection', options)

    def test_rejects_ambiguous_or_invalid_auth_before_connect(self):
        for connection in (
            'Server=local;Trusted_Connection=maybe;',
            'Server=local;Trusted_Connection=True;UID=u;',
            'Server=local;Trusted_Connection=True;PWD=secret;',
            'Server=local;Trusted_Connection=True;Integrated Security=SSPI;',
            'Server=local;Trusted_Connection=False;',
            'Server=local;Trusted_Connection=True;Database=other;',
            'Trusted_Connection=True;',
        ):
            with self.subTest(connection=connection):
                driver = SimpleNamespace(connect=Mock())
                with patch.dict(sys.modules, mssql_python=driver):
                    with self.assertRaises(ValueError):
                        sql_connection(connection)
                driver.connect.assert_not_called()

    def test_windows_login_error_does_not_expose_credentials(self):
        driver = SimpleNamespace(connect=Mock(side_effect=Exception('18456 login failed private data')))
        with patch.dict(sys.modules, mssql_python=driver):
            with self.assertRaisesRegex(ValueError, 'Tài khoản Windows') as error:
                sql_connection('Server=local;Trusted_Connection=True;')
        self.assertNotIn('private data', str(error.exception))


if __name__ == '__main__':
    unittest.main()
