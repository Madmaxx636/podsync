import 'package:flutter/material.dart';

import 'pal.dart';

/// A thin bar between two panels that you drag sideways to resize them, like the edge between
/// two table columns. Double-click it to put the panel back to its normal size.
class VerticalSplitter extends StatelessWidget {
  const VerticalSplitter({
    super.key,
    required this.onDrag,
    this.onReset,
    this.onEnd,
  });

  /// Called with how far the pointer moved sideways since the last call.
  final ValueChanged<double> onDrag;
  final VoidCallback? onReset;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      onHorizontalDragEnd: onEnd == null ? null : (_) => onEnd!(),
      onDoubleTap: onReset,
      child: SizedBox(
        width: 5,
        child: Center(child: Container(width: 1, color: Pal.of(context).rule)),
      ),
    ),
  );
}

/// The same, between a panel above and one below: drag up and down.
class HorizontalSplitter extends StatelessWidget {
  const HorizontalSplitter({super.key, required this.onDrag, this.onReset});

  final ValueChanged<double> onDrag;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeRow,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
      onDoubleTap: onReset,
      child: SizedBox(
        height: 5,
        child: Center(child: Container(height: 1, color: Pal.of(context).rule)),
      ),
    ),
  );
}
