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
    this.batchRepositoryFactory,
    this.directoryRepository,
    this.directoryRepositoryFactory,
    this.showTopBar = true,
  });
  final ReceiptProductType type;
  final BatchRepository? batchRepository;
  final BatchRepository Function()? batchRepositoryFactory;
  final DirectoryRepository? directoryRepository;
  final DirectoryRepository Function()? directoryRepositoryFactory;
  final bool showTopBar;
  @override
  State<GoodsReceiptScreen> createState() => _GoodsReceiptScreenState();
}

class _GoodsReceiptScreenState extends State<GoodsReceiptScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;
  late final BatchRepository _batches;
  late final bool _ownsBatches;
  DirectoryRepository? _directory;
  late final bool _ownsDirectory;
  int _index = 0;
  bool _visitedBatches = false;
  @override
  void initState() {
    super.initState();
    if (widget.showTopBar) _tabs = TabController(length: 2, vsync: this);
    if (widget.batchRepository != null) {
      _batches = widget.batchRepository!;
      _ownsBatches = false;
    } else {
      _batches =
          widget.batchRepositoryFactory?.call() ?? MongoBatchRepository();
      _ownsBatches = true;
    }
    if (widget.directoryRepository != null) {
      _directory = widget.directoryRepository;
      _ownsDirectory = false;
    } else if (widget.directoryRepositoryFactory != null) {
      _directory = widget.directoryRepositoryFactory!.call();
      _ownsDirectory = true;
    } else {
      _ownsDirectory = false;
    }
    if (!widget.showTopBar) _visitedBatches = true;
  }

  @override
  void dispose() {
    _tabs?.dispose();
    if (_ownsBatches) unawaited(_batches.close());
    if (_ownsDirectory) unawaited(_directory!.close());
    super.dispose();
  }

  Future<void> _openForm(ReceiptMode mode, {String? title}) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FormPopup(
        title:
            title ?? (mode == ReceiptMode.batch ? 'Nhập lô hàng' : 'Nhập lẻ'),
        child: GoodsReceiptFormScreen(
          type: widget.type,
          initialMode: mode,
          embedded: true,
          directoryRepository: _directory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showTopBar) {
      return BatchListView(
        type: widget.type,
        repository: _batches,
        directoryRepository: _directory,
        onCreate: () => _openForm(ReceiptMode.batch, title: 'Nhập lô'),
        onCreateSingle: () => _openForm(ReceiptMode.single, title: 'Nhập lẻ'),
      );
    }
    final body = Column(
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
              controller: _tabs!,
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
                directoryRepository: _directory,
              ),
              if (_visitedBatches)
                BatchListView(
                  type: widget.type,
                  repository: _batches,
                  directoryRepository: _directory,
                  onCreate: () => _openForm(ReceiptMode.batch),
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppTopBar(title: widget.type.title),
      body: body,
    );
  }
}
