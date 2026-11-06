import 'package:flutter/foundation.dart';
import '../models/dashboard/dashboard_group.dart';
import '../models/dashboard/dashboard_module.dart';

class DashboardController extends ChangeNotifier {
  DashboardGroup? _group;
  bool _salesActive = true;
  bool get salesActive => _salesActive;

  void openSales() {
    if (_salesActive) return;
    _salesActive = true;
    notifyListeners();
  }

  final Map<DashboardGroup, int> _selectedTabs = {};

  DashboardGroup? get group => _group;
  int get tabIndex => _group == null ? 0 : _selectedTabs[_group] ?? 0;
  DashboardModule? get module => _group?.modules[tabIndex];

  void selectGroup(DashboardGroup? group) {
    if (group == null) {
      openSales();
      return;
    }
    if (_group == group && !_salesActive) return;
    _salesActive = false;
    _group = group;
    notifyListeners();
  }

  void openModule(DashboardModule module) {
    final group = DashboardGroup.values.firstWhere(
      (g) => g.modules.contains(module),
    );
    _salesActive = false;
    _group = group;
    _selectedTabs[group] = group.modules.indexOf(module);
    notifyListeners();
  }

  void selectTab(int index) {
    final group = _group;
    if (group == null || index < 0 || index >= group.modules.length) return;
    if (tabIndex == index) return;
    _selectedTabs[group] = index;
    notifyListeners();
  }
}
