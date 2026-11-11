import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../models/pawn/pawn_models.dart';
import '../../models/printing/pawn_contract_data.dart';
import '../../services/pawn_contract_pdf.dart';
import '../widgets/app_top_bar.dart';

class PawnContractScreen extends StatefulWidget {
  const PawnContractScreen({super.key, required this.details});
  final PawnDetails details;
  @override
  State<PawnContractScreen> createState() => _PawnContractScreenState();
}

class _PawnContractScreenState extends State<PawnContractScreen> {
  PawnContractData? _data;
  String? _error;
  bool _building = false;
  @override
  void initState() {
    super.initState();
    try {
      _data = PawnContractData(widget.details);
    } catch (_) {
      _error =
          'Phiếu thiếu mã hoặc có số tiền không hợp lệ. Vui lòng kiểm tra lại phiếu.';
    }
  }

  Future<void> _preview() async {
    setState(() {
      _building = true;
      _error = null;
    });
    try {
      final bytes = await PawnContractPdf.build(_data!);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _ContractPreview(bytes: bytes, id: _data!.id),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Không tạo được bản in. Phiếu đã lưu vẫn được giữ nguyên. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  Widget _field(
    String label,
    String initial,
    ValueChanged<String> changed, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      initialValue: initial,
      enabled: !_building,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
      onChanged: changed,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppTopBar(
        title: 'In hợp đồng cầm đồ${data == null ? '' : ' #${data.id}'}',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data != null) ...[
                  Text(
                    'Số tiền: ${data.values['amount']} đồng',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Tài sản: ${data.asset}'),
                  const SizedBox(height: 12),
                  const Text(
                    'Hợp đồng theo mẫu Toàn Hợp đã cung cấp. Thông tin bổ sung chỉ dùng cho bản in này; mục để trống sẽ hiển thị dòng chấm để điền tay.',
                  ),
                  const SizedBox(height: 24),
                  _field(
                    'Người vay',
                    data.borrowerName,
                    (v) => data.borrowerName = v,
                  ),
                  _field('Số điện thoại', data.phone, (v) => data.phone = v),
                  _field(
                    'Địa chỉ đầy đủ',
                    data.address,
                    (v) => data.address = v,
                    lines: 2,
                  ),
                  _field(
                    'CMND / CCCD',
                    data.identityNumber,
                    (v) => data.identityNumber = v,
                  ),
                  _field(
                    'Ngày cấp (dd/MM/yyyy)',
                    data.identityDate,
                    (v) => data.identityDate = v,
                  ),
                  _field(
                    'Nơi cấp',
                    data.identityPlace,
                    (v) => data.identityPlace = v,
                  ),
                  _field(
                    'Người ủy quyền',
                    data.authorizedPerson,
                    (v) => data.authorizedPerson = v,
                  ),
                  FilledButton.icon(
                    onPressed: _building ? null : _preview,
                    icon: const Icon(Icons.print_outlined),
                    label: Text(
                      _building ? 'Đang tạo bản in…' : 'Xem trước & in',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Trong màn hình xem trước, chọn máy in hoặc lưu thành PDF.',
                  ),
                ],
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContractPreview extends StatelessWidget {
  const _ContractPreview({required this.bytes, required this.id});
  final Uint8List bytes;
  final int id;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(
      title: 'Hợp đồng cầm đồ #$id',
      actions: [
        IconButton(
          tooltip: 'Lưu PDF',
          icon: const Icon(Icons.save_alt),
          onPressed: () async {
            try {
              final location = await getSaveLocation(
                suggestedName: 'hop-dong-cam-do-$id.pdf',
                acceptedTypeGroups: [
                  const XTypeGroup(label: 'PDF', extensions: ['pdf']),
                ],
              );
              if (location == null) return;
              await XFile.fromData(
                bytes,
                mimeType: 'application/pdf',
                name: 'hop-dong-cam-do-$id.pdf',
              ).saveTo(location.path);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Không lưu được PDF. Vui lòng chọn lại nơi lưu.',
                    ),
                  ),
                );
              }
            }
          },
        ),
      ],
    ),
    body: PdfPreview(
      build: (_) async => bytes,
      pdfFileName: 'hop-dong-cam-do-$id.pdf',
      initialPageFormat: PdfPageFormat.letter,
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      allowSharing: false,
      onError: (_, _) => const Center(
        child: Text('Không hiển thị được bản in. Vui lòng thử lại.'),
      ),
      onPrintError: (context, _) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Không in được hợp đồng. Kiểm tra máy in và thử lại; phiếu đã lưu vẫn được giữ nguyên.',
          ),
        ),
      ),
    ),
  );
}
