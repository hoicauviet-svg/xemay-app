import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../../models/maintenance/record_maintenance.dart';
import '../../core/formatters/money_input_formatter.dart';
import '../widgets/editor_shell.dart';
import 'record_recovery_button.dart';

class RecordActions extends StatelessWidget {
  const RecordActions({
    super.key,
    required this.repository,
    required this.kind,
    required this.id,
    required this.onChanged,
    this.paymentId,
    this.onDeleted,
    this.onSelect,
  });
  final ValueChanged<bool>? onSelect;
  final RecordMaintenance? repository;
  final RecordKind kind;
  final int id;
  final dynamic paymentId;
  final Future<void> Function() onChanged;
  final VoidCallback? onDeleted;
  @override
  Widget build(BuildContext context) {
    if (repository == null) return const SizedBox.shrink();

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (paymentId == null)
            RecordRecoveryButton(repository: repository, onChanged: onChanged),
          IconButton(
            tooltip: paymentId == null ? 'Sửa phiếu' : 'Sửa phiếu trả nợ',
            onPressed: onSelect == null ? null : () => onSelect!(false),
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            tooltip: paymentId == null ? 'Xóa phiếu' : 'Xóa phiếu trả nợ',
            onPressed: onSelect == null ? null : () => onSelect!(true),
            icon: const Icon(
              Icons.delete_outline,
              color: Color(0xFFB44141),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class RecordEditor extends StatefulWidget {
  const RecordEditor({
    super.key,
    required this.repository,
    required this.kind,
    required this.id,
    required this.deleting,
    this.paymentId,
    this.embedded = false,
    this.onSaved,
    this.onDeleted,
    this.onCancel,
  });
  final bool embedded;
  final Future<void> Function()? onSaved;
  final VoidCallback? onDeleted, onCancel;
  final RecordMaintenance repository;
  final RecordKind kind;
  final int id;
  final dynamic paymentId;
  final bool deleting;
  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  final _form = GlobalKey<FormState>();
  final _text = <String, TextEditingController>{};
  final _dates = <String, DateTime?>{};
  final _draft = <String, dynamic>{};
  List<Map<String, dynamic>> _lines = [];
  Map<String, dynamic>? _payment;
  bool _loading = true, _saving = false, _locked = false;
  String? _error;
  String _request = ObjectId().oid;
  bool get isPayment => widget.paymentId != null;
  bool get incoming => widget.kind == RecordKind.batch;
  String get principal => switch (widget.kind) {
    RecordKind.order => 'SotienTra',
    RecordKind.batch => 'SoTienTra',
    RecordKind.pawn => 'TienGoc',
    RecordKind.funding => 'SoTienTraGoc',
    RecordKind.openingDebt => 'SoTienTra',
    _ => throw StateError('Không có phiếu trả nợ cho loại này'),
  };
  String get interest => switch (widget.kind) {
    RecordKind.funding => 'SoTienTraLai',
    RecordKind.pawn => 'SoTienLai',
    _ => 'LaiThu',
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _init(Map<String, dynamic> values) {
    _draft.addAll(values);
    for (final entry in values.entries) {
      if (entry.value is DateTime) {
        _dates[entry.key] = entry.value;
      }
    }
  }

  Future<void> _load() async {
    try {
      final data = await widget.repository.load(widget.kind, widget.id);
      if (!mounted) return;
      if (isPayment) {
        final idKey = switch (widget.kind) {
          RecordKind.order => 'IdTraNo',
          RecordKind.batch => 'IdTraNoNhapHang',
          RecordKind.pawn => 'IdTraNoCamDo',
          RecordKind.funding => 'IdTraNoVayVon',
          RecordKind.openingDebt => 'Id',
          _ => '_id',
        };
        _payment = data.payments.firstWhere(
          (p) => p['_id'] == widget.paymentId || p[idKey] == widget.paymentId,
        );
        _init(_payment!);
      } else {
        _init(data.header);
        _lines = [
          for (final row in data.lines) {...row},
        ];
      }
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không tải được thông tin phiếu. Đóng và mở lại để thử lại.';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController controller(String key, dynamic value) =>
      _text.putIfAbsent(
        key,
        () => TextEditingController(
          text: value is num
              ? value.toStringAsFixed(value % 1 == 0 ? 0 : 2)
              : '${value ?? ''}',
        ),
      );
  Widget input(
    String key,
    String label, {
    bool numeric = false,
    dynamic initial,
    bool optional = false,
  }) => TextFormField(
    controller: controller(key, initial ?? _draft[key]),
    enabled: !_saving && !_locked && _draft['_ManagedCash'] != true,
    keyboardType: numeric ? TextInputType.number : TextInputType.text,
    inputFormatters: numeric ? [MoneyInputFormatter()] : null,
    decoration: InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
    ),
    validator: (value) {
      if (!numeric) return null;
      if (optional && (value ?? '').trim().isEmpty) return null;
      final number = int.tryParse(
        (value ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
      );
      return number == null || number > 1000000000000000
          ? 'Nhập số không âm hợp lệ'
          : null;
    },
    onChanged: (value) => _draft[key] = numeric
        ? int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''))
        : value,
  );
  Widget date(String key, String label, {bool optional = false}) =>
      TextFormField(
        key: ValueKey('$key:${_dates[key]}'),
        initialValue: _dates[key] == null
            ? ''
            : DateFormat('dd/MM/yyyy').format(_dates[key]!),
        readOnly: true,
        enabled: !_saving && !_locked && _draft['_ManagedCash'] != true,
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        validator: (_) => !optional && _dates[key] == null ? 'Chọn ngày' : null,
        onTap: () async {
          final selected = await showDatePicker(
            context: context,
            initialDate: _dates[key] ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime(2200),
          );
          if (selected != null && mounted) {
            setState(() {
              _dates[key] = selected;
              _draft[key] = DateTime.utc(
                selected.year,
                selected.month,
                selected.day,
              );
            });
          }
        },
      );
  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (isPayment) {
        await widget.repository.payment(
          widget.kind,
          widget.id,
          widget.paymentId,
          widget.deleting ? null : _draft,
          requestId: _request,
          interestStart: _dates['_InterestStart'],
          nextAppointment: _dates['_NextAppointment'],
        );
      } else if (widget.deleting) {
        await widget.repository.delete(
          widget.kind,
          widget.id,
          requestId: _request,
        );
      } else {
        // Untouched numeric values remain in the draft; only editable line values are copied.
        for (var i = 0; i < _lines.length; i++) {
          for (final key in ['SoLuong', 'DonGia']) {
            if (_draft.containsKey('line:$i:$key')) {
              _lines[i][key] = _draft['line:$i:$key'];
            }
          }
        }
        await widget.repository.save(
          widget.kind,
          widget.id,
          _draft,
          _lines,
          requestId: _request,
        );
      }
      if (mounted) {
        if (widget.embedded) {
          if (widget.deleting && !isPayment) {
            widget.onDeleted?.call();
          } else {
            await widget.onSaved?.call();
          }
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  widget.deleting ? 'Đã xóa phiếu' : 'Đã lưu thay đổi',
                ),
              ),
            );
        } else {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locked = e is RecordChangeException && e.uncertain;
          if (!_locked) _request = ObjectId().oid;
          _error = e is RecordChangeException
              ? e.message
              : 'Chưa hoàn tất thay đổi. Vui lòng thử lại.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteInline() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa phiếu'),
        content: Text(
          widget.kind == RecordKind.pawn
              ? 'Xóa phiếu cầm đồ #${widget.id} và toàn bộ lịch sử thu gốc, thu lãi? Dư nợ và báo cáo sẽ thay đổi. Không thể hoàn tác từ màn hình này.'
              : 'Xóa phiếu này và cập nhật các số liệu liên quan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.delete(
        widget.kind,
        widget.id,
        requestId: _request,
      );
      if (mounted) widget.onDeleted?.call();
    } catch (e) {
      if (mounted)
        setState(() {
          _locked = e is RecordChangeException && e.uncertain;
          _error = '$e';
          if (!_locked) _request = ObjectId().oid;
        });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title =
        '${widget.deleting ? 'Xóa' : 'Sửa'} ${isPayment
            ? 'phiếu trả nợ'
            : incoming
            ? 'lô hàng'
            : widget.kind == RecordKind.pawn
            ? 'phiếu cầm đồ'
            : widget.kind == RecordKind.cash
            ? 'phiếu thu/chi'
            : 'đơn hàng'}';
    return PopScope(
      canPop: !_saving,
      child: EditorShell(
        embedded: widget.embedded,
        title: title,
        canClose: !_saving,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _form,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.deleting)
                                Text(
                                  isPayment
                                      ? 'Xóa phiếu trả nợ này? Công nợ, lịch sử và khoản thu lãi liên quan sẽ được cập nhật lại.'
                                      : widget.kind == RecordKind.pawn
                                      ? 'Xóa phiếu cầm đồ #${widget.id} và toàn bộ lịch sử thu gốc, thu lãi liên quan? Dư nợ và báo cáo cầm đồ sẽ thay đổi. Không thể hoàn tác từ màn hình này.'
                                      : incoming
                                      ? 'Xóa lô hàng #${widget.id}, sản phẩm nhập và các phiếu thanh toán liên quan? Tồn kho sẽ được giảm tương ứng. Lô có xe đã bán hoặc không đủ tồn phụ tùng sẽ không được xóa.'
                                      : 'Xóa đơn hàng #${widget.id} cùng chi tiết và các phiếu thu liên quan? Sản phẩm sẽ được hoàn lại tồn kho.',
                                ),
                              if (!widget.deleting && isPayment) ...[
                                date('NgayTra', 'Ngày trả'),
                                const SizedBox(height: 16),
                                input(
                                  principal,
                                  incoming ? 'Số tiền thanh toán' : 'Tiền gốc',
                                  numeric: true,
                                ),
                                if (!incoming) ...[
                                  const SizedBox(height: 16),
                                  input(
                                    interest,
                                    widget.kind == RecordKind.funding
                                        ? 'Tiền lãi đã trả'
                                        : 'Lãi thực thu',
                                    numeric: true,
                                    initial: _payment?[interest] ?? 0,
                                  ),
                                ],
                                if (widget.kind == RecordKind.order ||
                                    widget.kind == RecordKind.pawn ||
                                    widget.kind == RecordKind.openingDebt) ...[
                                  const SizedBox(height: 16),
                                  input(
                                    widget.kind == RecordKind.openingDebt
                                        ? 'TienLai'
                                        : widget.kind == RecordKind.pawn
                                        ? 'LaiThu'
                                        : 'SoTienLai',
                                    'Tiền lãi ghi nhận',
                                    numeric: true,
                                    initial:
                                        _payment?[widget.kind ==
                                                RecordKind.openingDebt
                                            ? 'TienLai'
                                            : widget.kind == RecordKind.pawn
                                            ? 'LaiThu'
                                            : 'SoTienLai'] ??
                                        0,
                                  ),
                                ],
                                if (widget.kind == RecordKind.order ||
                                    widget.kind == RecordKind.pawn) ...[
                                  const SizedBox(height: 16),
                                  date(
                                    widget.kind == RecordKind.order
                                        ? 'NgayHenSauTra'
                                        : 'NgayHen',
                                    'Ngày hẹn tiếp theo',
                                    optional: true,
                                  ),
                                ],
                                const SizedBox(height: 16),
                                input('GhiChu', 'Ghi chú'),
                              ],
                              if (isPayment &&
                                  widget.kind != RecordKind.batch &&
                                  widget.kind != RecordKind.pawn) ...[
                                const SizedBox(height: 16),
                                date(
                                  '_InterestStart',
                                  'Ngày tính lãi sau điều chỉnh (nếu cần)',
                                  optional: true,
                                ),
                              ],
                              if (isPayment &&
                                  (widget.kind == RecordKind.order ||
                                      widget.kind == RecordKind.pawn)) ...[
                                const SizedBox(height: 16),
                                date(
                                  '_NextAppointment',
                                  'Ngày hẹn sau điều chỉnh (nếu cần)',
                                  optional: true,
                                ),
                              ],
                              if (!widget.deleting &&
                                  !isPayment &&
                                  widget.kind == RecordKind.pawn) ...[
                                RecordReferenceField(
                                  repository: widget.repository,
                                  collection: 'KhachHang',
                                  label: 'Khách hàng',
                                  initialName:
                                      '${_draft['_CustomerName'] ?? ''}',
                                  initialId: _draft['IdKhachHang'],
                                  enabled: !_saving && !_locked,
                                  onSelected: (id) =>
                                      _draft['IdKhachHang'] = id,
                                ),
                                const SizedBox(height: 16),
                                input('TaiSanTheChap', 'Tài sản thế chấp'),
                                const SizedBox(height: 16),
                                input(
                                  'SoTienVay',
                                  'Số tiền vay',
                                  numeric: true,
                                ),
                                const SizedBox(height: 16),
                                date('NgayVay', 'Ngày vay'),
                                const SizedBox(height: 16),
                                date('NgayHan', 'Ngày hạn'),
                                const SizedBox(height: 16),
                                DropdownButtonFormField<bool>(
                                  initialValue: _draft['NgayPhanTram'] as bool?,
                                  decoration: const InputDecoration(
                                    labelText: 'Kiểu lãi',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: true,
                                      child: Text('Tiền/triệu/ngày'),
                                    ),
                                    DropdownMenuItem(
                                      value: false,
                                      child: Text('%/tháng'),
                                    ),
                                  ],
                                  onChanged: _saving || _locked
                                      ? null
                                      : (value) =>
                                            _draft['NgayPhanTram'] = value,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  initialValue: '${_draft['LaiSuat'] ?? ''}',
                                  enabled: !_saving && !_locked,
                                  decoration: const InputDecoration(
                                    labelText: 'Lãi suất',
                                  ),
                                  validator: (v) {
                                    final n = num.tryParse(
                                      (v ?? '').replaceAll(',', '.'),
                                    );
                                    return n == null || !n.isFinite || n < 0
                                        ? 'Nhập lãi suất không âm hợp lệ'
                                        : null;
                                  },
                                  onChanged: (v) => _draft['LaiSuat'] =
                                      num.tryParse(v.replaceAll(',', '.')),
                                ),
                                const SizedBox(height: 16),
                                CheckboxListTile(
                                  title: const Text('Đã chuộc / tất toán'),
                                  value: _draft['TrangThai'] == true,
                                  onChanged: _saving || _locked
                                      ? null
                                      : (value) => setState(
                                          () => _draft['TrangThai'] = value,
                                        ),
                                ),
                                input('GhiChu', 'Ghi chú'),
                              ],
                              if (!widget.deleting &&
                                  !isPayment &&
                                  widget.kind == RecordKind.cash) ...[
                                if (_draft['_ManagedCash'] == true)
                                  const Text(
                                    'Phiếu tự sinh từ sản phẩm hoặc trả nợ. Hãy sửa/xóa tại nguồn để đồng bộ số liệu.',
                                  ),
                                date('NgayThang', 'Ngày tháng'),
                                const SizedBox(height: 16),
                                DropdownButtonFormField<bool>(
                                  initialValue: _draft['ThuChi'] as bool?,
                                  decoration: const InputDecoration(
                                    labelText: 'Loại phiếu',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: true,
                                      child: Text('Thu'),
                                    ),
                                    DropdownMenuItem(
                                      value: false,
                                      child: Text('Chi'),
                                    ),
                                  ],
                                  onChanged:
                                      _saving ||
                                          _locked ||
                                          _draft['_ManagedCash'] == true
                                      ? null
                                      : (value) => setState(() {
                                          _draft['ThuChi'] = value;
                                          _draft['IdDanhMuc'] = null;
                                        }),
                                ),
                                const SizedBox(height: 16),
                                DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    'cash-category:${_draft['ThuChi']}:${_draft['IdDanhMuc']}',
                                  ),
                                  initialValue:
                                      (_draft['_CashCategories'] as List? ?? [])
                                          .any(
                                            (c) =>
                                                c['_id'] ==
                                                    _draft['IdDanhMuc'] &&
                                                c['ThuChi'] == _draft['ThuChi'],
                                          )
                                      ? _draft['IdDanhMuc'] as String?
                                      : null,
                                  decoration: const InputDecoration(
                                    labelText: 'Danh mục',
                                  ),
                                  items: [
                                    for (final category
                                        in _draft['_CashCategories'] as List? ??
                                            [])
                                      if (category['ThuChi'] ==
                                          _draft['ThuChi'])
                                        DropdownMenuItem(
                                          value: category['_id'] as String,
                                          child: Text(
                                            '${category['TenDanhMuc']}',
                                          ),
                                        ),
                                  ],
                                  onChanged:
                                      _saving ||
                                          _locked ||
                                          _draft['_ManagedCash'] == true
                                      ? null
                                      : (value) => _draft['IdDanhMuc'] = value,
                                  validator: (value) =>
                                      value == null ? 'Chọn danh mục' : null,
                                ),
                                const SizedBox(height: 16),
                                input('SoTien', 'Số tiền', numeric: true),
                                const SizedBox(height: 16),
                                input('LyDo', 'Nội dung'),
                              ],
                              if (!widget.deleting &&
                                  !isPayment &&
                                  (widget.kind == RecordKind.order ||
                                      widget.kind == RecordKind.batch)) ...[
                                date(
                                  incoming ? 'NgayNhap' : 'NgayMua',
                                  incoming ? 'Ngày nhập' : 'Ngày bán',
                                ),
                                const SizedBox(height: 16),
                                if (incoming) ...[
                                  RecordReferenceField(
                                    repository: widget.repository,
                                    collection: 'DoiTac',
                                    label: 'Đối tác / nhà cung cấp',
                                    initialName: '${_draft['NoiNhap'] ?? ''}',
                                    initialId: _draft['IdDoiTac'],
                                    enabled:
                                        !_saving &&
                                        !_locked &&
                                        _draft['_ManagedCash'] != true,
                                    onSelected: (id) => _draft['IdDoiTac'] = id,
                                  ),
                                  const SizedBox(height: 16),
                                  RecordReferenceField(
                                    repository: widget.repository,
                                    collection: 'VanChuyen',
                                    label: 'Vận chuyển',
                                    initialName: '${_draft['NguoiCho'] ?? ''}',
                                    initialId: _draft['IdVanChuyen'],
                                    enabled:
                                        !_saving &&
                                        !_locked &&
                                        _draft['_ManagedCash'] != true,
                                    onSelected: (id) =>
                                        _draft['IdVanChuyen'] = id,
                                  ),
                                  const SizedBox(height: 16),
                                  input(
                                    'SoLuong',
                                    'Số lượng khai báo',
                                    numeric: true,
                                  ),
                                  const SizedBox(height: 16),
                                  input(
                                    'SoTien',
                                    'Tổng tiền lô hàng',
                                    numeric: true,
                                  ),
                                ] else ...[
                                  RecordReferenceField(
                                    repository: widget.repository,
                                    collection: 'KhachHang',
                                    label: 'Khách hàng',
                                    initialName:
                                        '${_draft['_CustomerName'] ?? ''}',
                                    initialId: _draft['IdKH'],
                                    enabled:
                                        !_saving &&
                                        !_locked &&
                                        _draft['_ManagedCash'] != true,
                                    onSelected: (id) => _draft['IdKH'] = id,
                                  ),
                                  const SizedBox(height: 16),
                                  input(
                                    'GiamGia',
                                    'Giảm giá',
                                    numeric: true,
                                    initial: _draft['GiamGia'] ?? 0,
                                  ),
                                  const SizedBox(height: 16),
                                  date(
                                    'NgayHen',
                                    'Ngày hẹn thanh toán',
                                    optional: true,
                                  ),
                                  const SizedBox(height: 16),
                                  date(
                                    'NgayTinhLai',
                                    'Ngày tính lãi',
                                    optional: true,
                                  ),
                                  for (var i = 0; i < _lines.length; i++) ...[
                                    const Divider(height: 32),
                                    Text(
                                      '${_lines[i]['TenSanPham'] ?? 'Sản phẩm'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    if (_lines[i]['IdXe'] == null)
                                      input(
                                        'line:$i:SoLuong',
                                        'Số lượng',
                                        numeric: true,
                                        initial: _lines[i]['SoLuong'],
                                      ),
                                    const SizedBox(height: 16),
                                    input(
                                      'line:$i:DonGia',
                                      'Giá bán',
                                      numeric: true,
                                      initial:
                                          _lines[i]['DonGia'] ??
                                          _lines[i]['DonGiaNguon'],
                                    ),
                                  ],
                                ],
                                const SizedBox(height: 16),
                                input('GhiChu', 'Ghi chú'),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          if (widget.embedded && !isPayment && !widget.deleting)
                            TextButton.icon(
                              onPressed:
                                  _saving || _draft['_ManagedCash'] == true
                                  ? null
                                  : _deleteInline,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Xóa phiếu'),
                            ),
                          if (widget.onCancel != null)
                            TextButton(
                              onPressed: _saving ? null : widget.onCancel,
                              child: const Text('Quay lại thông tin'),
                            ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _saving || _draft['_ManagedCash'] == true
                                ? null
                                : _save,
                            icon: Icon(
                              widget.deleting
                                  ? Icons.delete_outline
                                  : Icons.save_outlined,
                            ),
                            label: Text(
                              _saving
                                  ? 'Đang xử lý…'
                                  : _locked
                                  ? 'Thử lại'
                                  : widget.deleting
                                  ? 'Xác nhận xóa'
                                  : 'Lưu thay đổi',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class RecordReferenceField extends StatefulWidget {
  const RecordReferenceField({
    super.key,
    required this.repository,
    required this.collection,
    required this.label,
    required this.initialName,
    required this.initialId,
    required this.enabled,
    required this.onSelected,
  });
  final RecordMaintenance repository;
  final String collection, label, initialName;
  final dynamic initialId;
  final bool enabled;
  final ValueChanged<dynamic> onSelected;
  @override
  State<RecordReferenceField> createState() => _RecordReferenceFieldState();
}

class _RecordReferenceFieldState extends State<RecordReferenceField> {
  late final _text = TextEditingController(text: widget.initialName);
  final _focus = FocusNode();
  bool _valid = true;
  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  String name(Map<String, dynamic> row) =>
      '${row[widget.collection == 'KhachHang'
              ? 'TenKhachHang'
              : widget.collection == 'DoiTac'
              ? 'TenDoiTac'
              : 'TenVanChuyen'] ?? ''}';
  @override
  Widget build(BuildContext context) => RawAutocomplete<Map<String, dynamic>>(
    textEditingController: _text,
    focusNode: _focus,
    displayStringForOption: name,
    optionsBuilder: (text) =>
        widget.repository.suggestions(widget.collection, text.text),
    onSelected: (row) {
      _valid = true;
      widget.onSelected(row[widget.collection == 'KhachHang' ? 'IdKH' : '_id']);
    },
    fieldViewBuilder: (context, text, focus, submit) => TextFormField(
      controller: text,
      focusNode: focus,
      enabled: widget.enabled,
      decoration: InputDecoration(
        labelText: widget.label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      onChanged: (value) {
        _valid = value == widget.initialName || value.trim().isEmpty;
        if (value.trim().isEmpty) widget.onSelected(null);
      },
      validator: (_) => _valid ? null : 'Chọn một kết quả trong danh sách',
    ),
    optionsViewBuilder: (context, select, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        child: SizedBox(
          width: 500,
          height: 240,
          child: ListView(
            children: [
              for (final row in options)
                ListTile(
                  title: Text(name(row)),
                  subtitle: Text('${row['SoDienThoai'] ?? ''}'),
                  onTap: () => select(row),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
