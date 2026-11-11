"""Time normal comparison on saved endpoints; business collections are read only."""
import json
from pathlib import Path
import sys
from time import monotonic
from datetime import datetime, timezone

from test_cloud_sync_live import saved_connections, ROOT
from cloud_sync import sync_cloud
from diagnostics import redact


def main():
    local, cloud = saved_connections()
    folder = ROOT / 'build/test-results'
    folder.mkdir(parents=True, exist_ok=True)
    started = monotonic()
    report = {'at': datetime.now(timezone.utc).isoformat(), 'success': False}
    with (folder / 'cloud-comparison-progress.log').open('w', encoding='utf-8') as log:
        def progress(message):
            log.write(f'{monotonic() - started:.2f}s {message}\n')
            log.flush()
        try:
            result = sync_cloud({'command': 'compareCloud', 'sourceUri': local, 'targetUri': cloud}, progress)
            report.update(success=True, seconds=round(monotonic() - started, 2),
                          sourceRows=result['sourceVersion']['rows'], targetRows=result['targetVersion']['rows'],
                          sourceCollections=result['sourceVersion']['collections'], targetCollections=result['targetVersion']['collections'],
                          sourceOnly=result['sourceOnly'], targetOnly=result['targetOnly'], conflicts=result['conflicts'],
                          identical=result['identical'], schemaConflicts=result['schemaConflicts'])
        except Exception as error:
            report.update(seconds=round(monotonic() - started, 2), errorType=type(error).__name__,
                          error=redact(str(error), {'sourceUri': local, 'targetUri': cloud}))
    (folder / 'cloud-comparison-benchmark.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
