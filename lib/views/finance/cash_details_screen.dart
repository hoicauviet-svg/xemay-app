import 'package:flutter/material.dart';
import '../../models/maintenance/record_maintenance.dart';
import '../../models/repositories/finance_repository.dart';
import '../maintenance/record_actions.dart';
import '../maintenance/record_recovery_button.dart';
import '../widgets/app_top_bar.dart';

class CashDetailsScreen extends StatefulWidget {
  const CashDetailsScreen({
    super.key,
    required this.id,
    required this.repository,
  });
  final int id;
  final FinanceRepository repository;
  @override
  State<CashDetailsScreen> createState() => _CashDetailsScreenState();
}

class _CashDetailsScreenState extends State<CashDetailsScreen> {
  int _revision = 0;
  Future<void> _refresh() async {
    if (mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 1,
    child: Scaffold(
      appBar: AppTopBar(
        title: 'Thu chi #${widget.id}',
        actions: [
          if (widget.repository.maintenance != null)
            RecordRecoveryButton(
              repository: widget.repository.maintenance,
              onChanged: _refresh,
            ),
        ],
        bottom: const TabBar(tabs: [Tab(text: 'Thông tin')]),
      ),
      body: widget.repository.maintenance == null
          ? const Center(
              child: Text('Chưa hỗ trợ chỉnh phiếu tại kết nối này.'),
            )
          : RecordEditor(
              key: ValueKey(_revision),
              repository: widget.repository.maintenance!,
              kind: RecordKind.cash,
              id: widget.id,
              deleting: false,
              embedded: true,
              onSaved: _refresh,
              onDeleted: () => Navigator.pop(context),
            ),
    ),
  );
}
