import 'package:flutter/material.dart';
import 'fixed_header_data_table.dart';

class ScrollableDataTable extends StatelessWidget {
  const ScrollableDataTable({
    super.key,
    required this.columns,
    this.rows = const [],
    this.rowCount,
    this.rowBuilder,
    this.footerRow,
    this.emptyContent,
    this.fixedHeader = false,
    this.columnWidths,
    this.fitWidth = false,
    this.rowHeight = 64,
    this.expandRows = false,
  });
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final int? rowCount;
  final DataRow Function(int)? rowBuilder;
  final DataRow? footerRow;
  final Widget? emptyContent;
  final bool fixedHeader;
  final List<double>? columnWidths;
  final bool fitWidth;
  final double rowHeight;
  final bool expandRows;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5EAED)),
    ),
    clipBehavior: Clip.antiAlias,
    child: fixedHeader
        ? FixedHeaderDataTable(
            columns: columns,
            rows: rows,
            rowCount: rowCount,
            rowBuilder: rowBuilder,
            footerRow: footerRow,
            emptyContent: emptyContent,
            columnWidths: columnWidths,
            fitWidth: fitWidth,
            rowHeight: rowHeight,
            expandRows: expandRows,
          )
        : LayoutBuilder(
            builder: (context, bounds) => SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: bounds.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: false,
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: expandRows ? double.infinity : 64,
                    columns: columns,
                    rows: rowBuilder == null
                        ? rows
                        : List.generate(rowCount ?? rows.length, rowBuilder!),
                  ),
                ),
              ),
            ),
          ),
  );
}
