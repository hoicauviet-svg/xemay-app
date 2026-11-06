import 'dart:async';
import 'package:flutter/material.dart';
import '../../controllers/directory_controller.dart';
import '../../models/directory/directory_models.dart';
import '../../models/repositories/directory_repository.dart';
import '../../services/mongo_directory_repository.dart';
import 'directory_management_popup.dart';

class CarrierTab extends StatefulWidget {
  const CarrierTab({super.key, this.repository});
  final DirectoryRepository? repository;

  @override
  State<CarrierTab> createState() => _CarrierTabState();
}

class _CarrierTabState extends State<CarrierTab> {
  late final _directory = DirectoryController(
    widget.repository ?? MongoDirectoryRepository(),
  );

  @override
  void dispose() {
    _directory.dispose();
    unawaited(_directory.repository.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DirectoryManagementPopup(
    directory: _directory,
    kind: DirectoryKind.carrier,
    embedded: true,
  );
}
