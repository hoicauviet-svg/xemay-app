import '../../models/repositories/database_settings_repository.dart';
import '../../core/config/database_config.dart';
import '../settings/app_update_panel.dart';
import '../settings/settings_tab.dart';
import '../settings/cloud_sync_reminder_dialog.dart';
import '../../services/native_database_settings_repository.dart';
import '../../models/repositories/opening_debt_repository.dart';
import '../../models/repositories/reports_repository.dart';
import '../reports/reports_view.dart';
import '../finance/opening_debt_tab.dart';
import '../../models/repositories/finance_repository.dart';
import '../finance/finance_tab.dart';
import '../../models/repositories/pawn_repository.dart';
import '../pawn/pawn_tab.dart';
import 'package:flutter/material.dart';
import '../../models/repositories/inventory_repository.dart';
import '../../models/repositories/customer_repository.dart';
import '../../models/repositories/partner_repository.dart';
import '../../models/repositories/service_repository.dart';
import '../../models/repositories/sales_repository.dart';
import '../../models/repositories/batch_repository.dart';
import '../../models/repositories/directory_repository.dart';
import '../../services/mongo_sales_repository.dart';
import 'dart:async';
import '../directory/partner_tab.dart';
import '../directory/carrier_tab.dart';
import '../customers/customer_tab.dart';
import '../customers/customer_merge_tab.dart';
import '../../models/dashboard/dashboard_group.dart';
import '../../controllers/dashboard_controller.dart';
import '../../controllers/sales_controller.dart';
import '../../controllers/cart_controller.dart';
import '../../services/mongo_customer_repository.dart';
import '../products/product_tab.dart';
import '../products/service_tab.dart';
import '../goods_receipt/goods_receipt_screen.dart';
import '../../models/goods_receipt/goods_receipt_models.dart';
import '../../models/dashboard/dashboard_module.dart';
import '../cart/dashboard_cart_button.dart';
import '../sales/sales_tab.dart';

const _ink = Color(0xFF1D3036);
const _muted = Color(0xFF6E7D83);
const _green = Color(0xFF176455);
const _border = Color(0xFFE5EAED);

/// Business groups in the sidebar, with a tab per child function.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.inventoryRepositoryFactory,
    this.customerRepositoryFactory,
    this.partnerRepositoryFactory,
    this.serviceRepositoryFactory,
    this.directoryRepositoryFactory,
    this.batchRepositoryFactory,
    this.pawnRepositoryFactory,
    this.financeRepositoryFactory,
    this.openingDebtRepositoryFactory,
    this.reportsRepositoryFactory,
    this.databaseSettingsRepositoryFactory,
    this.salesRepositoryFactory,
  });
  final InventoryRepository Function()? inventoryRepositoryFactory;
  final CustomerRepository Function()? customerRepositoryFactory;
  final PartnerRepository Function()? partnerRepositoryFactory;
  final ServiceRepository Function()? serviceRepositoryFactory;
  final DirectoryRepository Function()? directoryRepositoryFactory;
  final BatchRepository Function()? batchRepositoryFactory;
  final PawnRepository Function()? pawnRepositoryFactory;
  final FinanceRepository Function()? financeRepositoryFactory;
  final OpeningDebtRepository Function()? openingDebtRepositoryFactory;
  final ReportsRepository Function()? reportsRepositoryFactory;
  final DatabaseSettingsRepository Function()?
  databaseSettingsRepositoryFactory;
  final SalesRepository Function()? salesRepositoryFactory;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _controller = DashboardController();
  late SalesController _sales;
  StreamSubscription<int>? _databaseSubscription;
  int _databaseRevision = DatabaseConfig.revision;
  int _initialSettingsTab = 0;
  @override
  void initState() {
    super.initState();
    if (DatabaseConfig.startupReadFailed) {
      _controller.selectGroup(DashboardGroup.settings);
    }
    _createSalesController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_startupNotices());
    });
    _databaseSubscription = DatabaseConfig.changes.listen((revision) {
      if (!mounted) return;
      _sales.dispose();
      _createSalesController();
      setState(() => _databaseRevision = revision);
    });
  }

  Future<void> _startupNotices() async {
    await checkForCloudSyncReminder(
      context,
      repository:
          widget.databaseSettingsRepositoryFactory?.call() ??
          NativeDatabaseSettingsRepository(),
      onOpenSettings: () {
        setState(() => _initialSettingsTab = 2);
        _selectGroup(DashboardGroup.settings);
      },
    );
    if (mounted) await checkForUpdateOnLaunch(context);
  }

  void _createSalesController() {
    _sales = SalesController(
      CartController.shared,
      widget.customerRepositoryFactory?.call() ?? MongoCustomerRepository(),
      salesRepository:
          widget.salesRepositoryFactory?.call() ?? MongoSalesRepository(),
    );
    unawaited(_sales.recover());
  }

  void _openProductTab(int index) {
    _selectGroup(DashboardGroup.products);
    _controller.selectTab(index);
  }

  final _scaffold = GlobalKey<ScaffoldState>();

  void _selectGroup(DashboardGroup? group) {
    _scaffold.currentState?.closeDrawer();
    _controller.selectGroup(group);
  }

  void _openSales() {
    _scaffold.currentState?.closeDrawer();
    _controller.openSales();
  }

  @override
  void dispose() {
    unawaited(_databaseSubscription?.cancel());
    _sales.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 1050;
        final sidebar = _Sidebar(
          group: _controller.group,
          onSelect: _selectGroup,
          salesActive: _controller.salesActive,
          onOpenSales: _openSales,
        );
        return Scaffold(
          key: _scaffold,
          appBar: wide
              ? null
              : AppBar(
                  actions: [
                    DashboardCartButton(compact: true, onPressed: _openSales),
                    const SizedBox(width: 8),
                  ],
                ),
          drawer: wide ? null : Drawer(child: sidebar),
          body: Row(
            children: [
              if (wide) SizedBox(width: 260, child: sidebar),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child:
                          _controller.salesActive || _controller.group == null
                          ? SalesTab(
                              key: ValueKey(_databaseRevision),
                              controller: _sales,
                              onAddProducts: () => _openProductTab(0),
                              onAddServices: () => _openProductTab(3),
                            )
                          : _GroupTabs(
                              controller: _controller,
                              initialSettingsTab: _initialSettingsTab,
                              databaseRevision: _databaseRevision,
                              inventoryRepositoryFactory:
                                  widget.inventoryRepositoryFactory,
                              customerRepositoryFactory:
                                  widget.customerRepositoryFactory,
                              partnerRepositoryFactory:
                                  widget.partnerRepositoryFactory,
                              serviceRepositoryFactory:
                                  widget.serviceRepositoryFactory,
                              directoryRepositoryFactory:
                                  widget.directoryRepositoryFactory,
                              batchRepositoryFactory:
                                  widget.batchRepositoryFactory,
                              pawnRepositoryFactory:
                                  widget.pawnRepositoryFactory,
                              financeRepositoryFactory:
                                  widget.financeRepositoryFactory,
                              openingDebtRepositoryFactory:
                                  widget.openingDebtRepositoryFactory,
                              reportsRepositoryFactory:
                                  widget.reportsRepositoryFactory,
                              databaseSettingsRepositoryFactory:
                                  widget.databaseSettingsRepositoryFactory,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

IconData _groupIcon(DashboardGroup group) => switch (group) {
  DashboardGroup.goodsReceipt => Icons.move_to_inbox_outlined,
  DashboardGroup.products => Icons.inventory_2_outlined,
  DashboardGroup.customers => Icons.people_outline,
  DashboardGroup.partners => Icons.business_outlined,
  DashboardGroup.pawn => Icons.handshake_outlined,
  DashboardGroup.finance => Icons.account_balance_wallet_outlined,
  DashboardGroup.reports => Icons.bar_chart_outlined,
  DashboardGroup.settings => Icons.settings_outlined,
};

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.group,
    required this.onSelect,
    required this.salesActive,
    required this.onOpenSales,
  });
  final bool salesActive;
  final VoidCallback onOpenSales;
  final DashboardGroup? group;
  final ValueChanged<DashboardGroup?> onSelect;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: Container(
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: _border)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 28, 16, 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.storefront_outlined,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CỬA HÀNG',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: _ink,
                          ),
                        ),
                        Text(
                          'Xe & phụ tùng',
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DashboardCartButton(
                      onPressed: onOpenSales,
                      selected: salesActive,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 24, 12, 10),
                    child: Text(
                      'NGHIỆP VỤ CỬA HÀNG',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        color: _muted,
                      ),
                    ),
                  ),
                  for (final item in DashboardGroup.values)
                    ListTile(
                      dense: true,
                      selected: group == item && !salesActive,
                      selectedColor: _green,
                      selectedTileColor: const Color(0xFFEAF3EF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      leading: Icon(_groupIcon(item), size: 20),
                      title: Text(
                        item.label,
                        style: const TextStyle(fontSize: 13),
                      ),
                      onTap: () => onSelect(item),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GroupTabs extends StatelessWidget {
  const _GroupTabs({
    required this.controller,
    this.databaseRevision = 0,
    this.initialSettingsTab = 0,
    this.inventoryRepositoryFactory,
    this.customerRepositoryFactory,
    this.partnerRepositoryFactory,
    this.serviceRepositoryFactory,
    this.directoryRepositoryFactory,
    this.batchRepositoryFactory,
    this.pawnRepositoryFactory,
    this.financeRepositoryFactory,
    this.openingDebtRepositoryFactory,
    this.reportsRepositoryFactory,
    this.databaseSettingsRepositoryFactory,
  });
  final InventoryRepository Function()? inventoryRepositoryFactory;
  final CustomerRepository Function()? customerRepositoryFactory;
  final PartnerRepository Function()? partnerRepositoryFactory;
  final ServiceRepository Function()? serviceRepositoryFactory;
  final DirectoryRepository Function()? directoryRepositoryFactory;
  final BatchRepository Function()? batchRepositoryFactory;
  final PawnRepository Function()? pawnRepositoryFactory;
  final FinanceRepository Function()? financeRepositoryFactory;
  final OpeningDebtRepository Function()? openingDebtRepositoryFactory;
  final ReportsRepository Function()? reportsRepositoryFactory;
  final DatabaseSettingsRepository Function()?
  databaseSettingsRepositoryFactory;
  final DashboardController controller;
  final int databaseRevision;
  final int initialSettingsTab;

  @override
  Widget build(BuildContext context) {
    final group = controller.group!;
    if (group == DashboardGroup.settings) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SettingsTab(
          key: ValueKey('settings-initial-$initialSettingsTab'),
          initialTab: initialSettingsTab,
          repository: databaseSettingsRepositoryFactory?.call(),
        ),
      );
    }
    if (group == DashboardGroup.reports) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: ReportsView(
          key: ValueKey(databaseRevision),
          repository: reportsRepositoryFactory?.call(),
          onOpenProductTab: controller.openModule,
          onOpenFundingLoans: () =>
              controller.openModule(DashboardModule.fundingLoans),
          onOpenOpeningDebt: () =>
              controller.openModule(DashboardModule.openingDebt),
        ),
      );
    }
    return DefaultTabController(
      key: ValueKey((group, databaseRevision)),
      length: group.modules.length,
      initialIndex: controller.tabIndex,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                labelColor: _green,
                unselectedLabelColor: _muted,
                indicatorColor: _green,
                onTap: controller.selectTab,
                tabs: [
                  for (final module in group.modules) Tab(text: module.label),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final module in group.modules)
                    if (module == DashboardModule.receiptNewVehicles ||
                        module == DashboardModule.receiptUsedVehicles ||
                        module == DashboardModule.receiptParts)
                      GoodsReceiptScreen(
                        key: ValueKey(module),
                        showTopBar: false,
                        batchRepositoryFactory: batchRepositoryFactory,
                        directoryRepositoryFactory: directoryRepositoryFactory,
                        type: switch (module) {
                          DashboardModule.receiptUsedVehicles =>
                            ReceiptProductType.usedVehicle,
                          DashboardModule.receiptParts =>
                            ReceiptProductType.part,
                          _ => ReceiptProductType.newVehicle,
                        },
                      )
                    else if (module == DashboardModule.services)
                      ServiceTab(repository: serviceRepositoryFactory?.call())
                    else if (module == DashboardModule.pawnContracts)
                      PawnTab(
                        repository: pawnRepositoryFactory?.call(),
                        customers: customerRepositoryFactory?.call(),
                      )
                    else if (module == DashboardModule.cashbook ||
                        module == DashboardModule.fundingLoans)
                      FinanceTab(
                        loans: module == DashboardModule.fundingLoans,
                        repository: financeRepositoryFactory?.call(),
                      )
                    else if (module == DashboardModule.openingDebt)
                      OpeningDebtTab(
                        repository: openingDebtRepositoryFactory?.call(),
                      )
                    else if (group == DashboardGroup.products)
                      ProductTab(
                        key: ValueKey(module),
                        module: module,
                        repository: inventoryRepositoryFactory?.call(),
                        directoryRepositoryFactory: directoryRepositoryFactory,
                      )
                    else if (module == DashboardModule.customerMerge)
                      CustomerMergeTab(
                        repository: customerRepositoryFactory?.call(),
                      )
                    else if (group == DashboardGroup.customers)
                      CustomerTab(repository: customerRepositoryFactory?.call())
                    else if (module == DashboardModule.carriers)
                      CarrierTab(repository: directoryRepositoryFactory?.call())
                    else if (group == DashboardGroup.partners)
                      PartnerTab(repository: partnerRepositoryFactory?.call())
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _border),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
