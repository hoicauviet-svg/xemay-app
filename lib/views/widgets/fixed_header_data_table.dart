import 'package:flutter/material.dart';

/// One horizontal viewport keeps the fixed header and scrolling rows aligned.
class FixedHeaderDataTable extends StatefulWidget {
  const FixedHeaderDataTable({
    super.key,
    required this.columns,
    this.rows = const [],
    this.rowCount,
    this.rowBuilder,
    this.footerRow,
    this.emptyContent,
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
  final List<double>? columnWidths;
  final bool fitWidth;
  final double rowHeight;
  final bool expandRows;
  @override
  State<FixedHeaderDataTable> createState() => _FixedHeaderDataTableState();
}

class _FixedHeaderDataTableState extends State<FixedHeaderDataTable> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final widths =
          widget.columnWidths ?? List.filled(widget.columns.length, 180.0);
      assert(widths.length == widget.columns.length);
      final baseWidth = widths.fold<double>(0, (sum, value) => sum + value);
      final scale = widget.fitWidth ? bounds.maxWidth / baseWidth : 1.0;
      final extra = !widget.fitWidth && bounds.maxWidth > baseWidth
          ? (bounds.maxWidth - baseWidth) / widths.length
          : 0.0;
      final tableWidth = baseWidth * scale + extra * widths.length;
      final columnWidths = {
        for (var i = 0; i < widths.length; i++)
          i: FixedColumnWidth(widths[i] * scale + extra),
      };
      final headingStyle =
          Theme.of(context).dataTableTheme.headingTextStyle ??
          const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF56656D),
          );
      return SingleChildScrollView(
        key: const ValueKey('fixed-table-horizontal'),
        controller: _horizontal,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          height: bounds.maxHeight,
          child: Material(
            color: Colors.white,
            child: Column(
              children: [
                Container(
                  key: const ValueKey('fixed-table-heading'),
                  color: const Color(0xFFF8FAFB),
                  child: DefaultTextStyle(
                    style: headingStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    child: Table(
                      columnWidths: columnWidths,
                      children: [
                        TableRow(
                          children: [
                            for (var i = 0; i < widget.columns.length; i++)
                              _cell(
                                widget.columns[i].label,
                                widget.columns[i].numeric,
                                height: 56,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE5EAED),
                ),
                Expanded(
                  child:
                      (widget.rowCount ?? widget.rows.length) == 0 &&
                          widget.emptyContent != null
                      ? widget.emptyContent!
                      : widget.rowBuilder != null
                      ? ListView.builder(
                          key: const ValueKey('fixed-table-body'),
                          controller: _vertical,
                          itemCount: widget.rowCount ?? widget.rows.length,
                          itemBuilder: (context, index) => Container(
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Color(0xFFE5EAED),
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Table(
                              columnWidths: columnWidths,
                              children: [_tableRow(widget.rowBuilder!(index))],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          key: const ValueKey('fixed-table-body'),
                          controller: _vertical,
                          child: Table(
                            columnWidths: columnWidths,
                            border: const TableBorder(
                              horizontalInside: BorderSide(
                                color: Color(0xFFE5EAED),
                                width: 0.5,
                              ),
                            ),
                            children: [
                              for (final row in widget.rows) _tableRow(row),
                            ],
                          ),
                        ),
                ),
                if (widget.footerRow != null)
                  Container(
                    key: const ValueKey('fixed-table-footer'),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF0F6F3),
                      border: Border(top: BorderSide(color: Color(0xFFD8E5DE))),
                    ),
                    child: Table(
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      columnWidths: columnWidths,
                      children: [_tableRow(widget.footerRow!, footer: true)],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  TableRow _tableRow(DataRow row, {bool footer = false}) => TableRow(
    children: [
      for (var i = 0; i < row.cells.length; i++)
        DefaultTextStyle(
          style: footer
              ? DefaultTextStyle.of(context).style.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF176455),
                )
              : DefaultTextStyle.of(context).style,
          maxLines: widget.expandRows || footer ? null : 2,
          overflow: widget.expandRows || footer
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
          child: _cell(
            row.cells[i].child,
            widget.columns[i].numeric,
            height: widget.rowHeight,
            expand: widget.expandRows || footer,
            onTap:
                row.cells[i].onTap ??
                (row.onSelectChanged == null
                    ? null
                    : () => row.onSelectChanged!(!row.selected)),
          ),
        ),
    ],
  );

  Widget _cell(
    Widget child,
    bool numeric, {
    double height = 64,
    VoidCallback? onTap,
    bool expand = false,
  }) => ConstrainedBox(
    constraints: BoxConstraints(
      minHeight: height,
      maxHeight: expand ? double.infinity : height,
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.fitWidth ? 10 : 16,
          vertical: 8,
        ),
        child: Align(
          heightFactor: expand ? 1 : null,
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      ),
    ),
  );
}
