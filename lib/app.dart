import 'models/repositories/database_settings_repository.dart';
import 'models/repositories/opening_debt_repository.dart';
import 'models/repositories/reports_repository.dart';
import 'models/repositories/finance_repository.dart';
import 'models/repositories/pawn_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'models/repositories/inventory_repository.dart';
import 'models/repositories/customer_repository.dart';
import 'models/repositories/partner_repository.dart';
import 'models/repositories/service_repository.dart';
import 'models/repositories/sales_repository.dart';
import 'models/repositories/batch_repository.dart';
import 'models/repositories/directory_repository.dart';
import 'views/dashboard/dashboard_screen.dart';

class StoreApp extends StatelessWidget {
  const StoreApp({
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
  Widget build(BuildContext context) => MaterialApp(
    title: 'Xe Máy Toàn Hợp',
    debugShowCheckedModeBanner: false,
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: AppTheme.light,
    home: DashboardScreen(
      inventoryRepositoryFactory: inventoryRepositoryFactory,
      customerRepositoryFactory: customerRepositoryFactory,
      partnerRepositoryFactory: partnerRepositoryFactory,
      serviceRepositoryFactory: serviceRepositoryFactory,
      directoryRepositoryFactory: directoryRepositoryFactory,
      batchRepositoryFactory: batchRepositoryFactory,
      pawnRepositoryFactory: pawnRepositoryFactory,
      financeRepositoryFactory: financeRepositoryFactory,
      openingDebtRepositoryFactory: openingDebtRepositoryFactory,
      reportsRepositoryFactory: reportsRepositoryFactory,
      databaseSettingsRepositoryFactory: databaseSettingsRepositoryFactory,
      salesRepositoryFactory: salesRepositoryFactory,
    ),
  );
}
