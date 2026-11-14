import 'package:flutter/material.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/finance/finance_list_report.dart';
import '../../models/reports/report_models.dart';
import '../../services/report_excel_service.dart';

class FinanceTotalsStrip extends StatelessWidget {
  const FinanceTotalsStrip({
    super.key,
    required this.totals,
    this.quantityLabels = const {},
  });
  final Map<String, num?> totals;
  final Set<String> quantityLabels;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    color: const Color(0xFFF0F6F3),
    child: Wrap(
      spacing: 20,
      runSpacing: 8,
      children: [
        for (final e in totals.entries)
          Text(
            '${e.key}: ${e.value == null
                ? ''
                : quantityLabels.contains(e.key)
                ? quantity(e.value!)
                : money(e.value)}',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF176455),
            ),
          ),
      ],
    ),
  );
}

class FinanceExcelButton extends StatefulWidget {
  const FinanceExcelButton({
    super.key,
    required this.title,
    required this.section,
    required this.loadedAt,
    this.exporter,
    this.kind = ReportKind.debts,
  });
  final String title;
  final ReportSection section;
  final DateTime loadedAt;
  final FinanceReportExporter? exporter;
  final ReportKind kind;
  @override
  State<FinanceExcelButton> createState() => _FinanceExcelButtonState();
}

class _FinanceExcelButtonState extends State<FinanceExcelButton> {
  bool _saving = false;
  Future<void> _save() async {
    final title = widget.title,
        section = widget.section,
        time = widget.loadedAt;
    setState(() => _saving = true);
    try {
      final saved = widget.exporter == null
          ? await ReportExcelService.saveNamed(
              title,
              section,
              time,
              kind: widget.kind,
            )
          : await widget.exporter!(title, section, time);
      if (saved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Xuất Excel thành công')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa xuất được Excel. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: _saving ? null : _save,
    icon: _saving
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.download_outlined),
    label: Text(_saving ? 'Đang xuất…' : 'Xuất Excel'),
  );
}
