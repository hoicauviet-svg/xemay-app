import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/goods_receipt/goods_receipt_models.dart';
import '../../models/repositories/batch_repository.dart';
import '../../models/repositories/directory_repository.dart';
import '../../services/mongo_batch_repository.dart';
import '../batches/batch_list_view.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/form_popup.dart';
import 'goods_receipt_form_screen.dart';

/// Entry workspace: single-item entry first, followed by the lot browser.
class GoodsReceiptScreen extends StatefulWidget {
  const GoodsReceiptScreen({
    super.key,
    required this.type,
    this.batchRepository,
    this.directoryRepository,
  });
  final ReceiptProductType type;
  final BatchRepository? batchRepository;
  final DirectoryRepository? directoryRepository;
  @override
  State<GoodsReceiptScreen> createState() => _GoodsReceiptScreenState();
}

class _GoodsReceiptScreenState extends State<GoodsReceiptScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final BatchRepository _batches;
  int _index = 0;
  bool _visitedBatches = false;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _batches = widget.batchRepository ?? MongoBatchRepository();
  }

  @override
  void dispose() {
    _tabs.dispose();
    if (widget.batchRepository == null) unawaited(_batches.close());
    super.dispose();
  }

  Future<void> _newBatch() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FormPopup(
        title: 'Nhập lô hàng',
        child: GoodsReceiptFormScreen(
          type: widget.type,
          initialMode: ReceiptMode.batch,
          embedded: true,
          directoryRepository: widget.directoryRepository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(title: widget.type.title),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5EAED)),
            ),
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: const Color(0xFF176455),
              unselectedLabelColor: const Color(0xFF6E7D83),
              indicatorColor: const Color(0xFF176455),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Nhập lẻ'),
                Tab(text: 'Lô hàng'),
              ],
              onTap: (index) {
                FocusScope.of(context).unfocus();
                setState(() {
                  _index = index;
                  if (index == 1) _visitedBatches = true;
                });
              },
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [
              GoodsReceiptFormScreen(
                type: widget.type,
                embedded: true,
                directoryRepository: widget.directoryRepository,
              ),
              if (_visitedBatches)
                BatchListView(
                  type: widget.type,
                  repository: _batches,
                  directoryRepository: widget.directoryRepository,
                  onCreate: _newBatch,
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    ),
  );
}
