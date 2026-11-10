import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from diagnostics import record_error


class DiagnosticsTests(unittest.TestCase):
    def test_records_hidden_driver_error_without_password(self):
        secret = 'private;pa}ss'
        request = {'command': 'probeSql', 'sqlConnection': 'Server=local;UID=private-user;PWD={private;pa}}ss};'}
        try:
            try:
                raise OSError('08001 TLS certificate validation failed; UID=private-user; PWD={private;pa}}ss}; ' + secret)
            except OSError:
                raise RuntimeError('SQL connection failed') from None
        except RuntimeError as error:
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'logs' / 'database-helper.log'
                self.assertEqual(record_error(error, request, path), str(path))
                raw = path.read_text(encoding='utf-8')
                entry = json.loads(raw)
                self.assertIn('08001', entry['details'])
                self.assertIn('TLS certificate validation failed', entry['details'])
                self.assertIn('OSError', entry['details'])
                self.assertIn('RuntimeError', entry['details'])
                self.assertIn('test_diagnostics.py', entry['details'])
                self.assertEqual(entry['command'], 'probeSql')
                for value in (secret, 'private;pa}}ss', 'private-user', request['sqlConnection']):
                    self.assertNotIn(value, raw)

    def test_mongo_credentials_are_hidden_and_multiple_entries_append(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'error.log'
            for _ in range(2):
                record_error(ValueError('mongodb://alice:secret@localhost/XM'), {'command': 'clone'}, path)
            lines = path.read_text().splitlines()
            self.assertEqual(len(lines), 2)
            self.assertNotIn('alice', ''.join(lines))
            self.assertNotIn('secret', ''.join(lines))

    def test_logging_failure_does_not_hide_sql_error(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'not-a-directory'
            path.write_text('occupied')
            self.assertIsNone(record_error(RuntimeError('SQL failed'), {}, path / 'error.log'))


if __name__ == '__main__':
    unittest.main()
