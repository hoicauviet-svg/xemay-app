# Database settings and cloning

The app packages `xemay_database_helper` as a Flutter asset. It includes Python,
PyMongo and Microsoft's mssql-python driver. Source and pinned build dependencies are
in this directory; rebuild with `python tool/build_database_helper.py` from an
isolated environment containing `requirements-build.txt`. The checked-in helper is
the Apple Silicon build. The Windows `.exe` is produced on Windows, including by
GitHub Actions, and is not stored in git. SQL support on macOS requires macOS 15+
and OpenSSL, as documented by Microsoft. MongoDB Community is installed separately
using the link in Settings.

Connection strings are stored together in the macOS Keychain. macOS passes them
on standard input. On Windows the frozen helper cannot read a redirected pipe,
so the app writes the request to a private temporary file, passes only that
path, and the helper deletes the file as soon as it has read it. Credentials
never appear in logs or migration reports.
Runtime MongoDB URIs support regular hosts, multiple hosts and DNS seed lists;
missing database paths default to XM. New database URIs preserve the original
MongoDB authentication database.

The desktop app intentionally runs outside the macOS App Sandbox to execute its
bundled database helper and inspect locally installed MongoDB/OpenSSL. These are
local desktop distribution entitlements, not an App Store sandbox profile.

SQL operations are limited to metadata SELECTs, table SELECTs, transaction isolation
and commit. Views, procedures and functions are excluded. A serializable transaction
keeps the source snapshot consistent. Original SQL rows and metadata are exported
into a private Application Support backup folder before normalization.

Every clone uses a new `<configured_database>_import_<timestamp>_<random>` database.
The configured database is never overwritten, renamed or dropped. The helper checks
that its new destination is empty, verifies every inserted document by BSON hash,
installs application validators/indexes and records transformation metadata. The UI
requires a separate action to start using the verified clone. Switching is blocked
while the shared sales cart contains items or is locked. Saving a connection reloads
repositories without restarting the app.

Transformations mirror the previous XM migrations: recursively archive orphan rows,
preserve optional unset references, normalize the catalog and individual vehicles,
separate partners/carriers and seller roles, merge historical purchase orders into
fully paid receipt lots, enable services/discounts/debt dates/expense validation,
populate known legacy sale totals and apply the explicitly confirmed order #1826
correction only when its source identity, price, payment history and original
balances match. Other questionable balances are preserved for reconciliation.
Historical interest cash vouchers are retained; interest is not copied again from
TraNo to ThuChiKhac. Expense arrays and future interest receipts continue through
normal application repositories.

Tests: `tool/check_database_clone.py` validates the retained 143111-row SQL export
against an isolated temporary MongoDB, plus connection parsing, guarded corrections,
checksums, validators and overwrite refusal. Widget/controller tests cover both tabs,
installation prompts, connection saves, explicit clone activation and sales-cart
protection. `tool/check_database_protocol.py` checks the packaged helper protocol and
redaction using test-only credentials.
