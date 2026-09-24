import 'package:flutter/material.dart';

/// Pinterest-style layout: pictures sit side by side in columns, each
/// keeping its own proportions, with no gaps between rows. Items are
/// dealt out to the columns in turn, which keeps the columns roughly the
/// same height. Meant to live inside a scroll view (it does not scroll
/// on its own).
class MasonryGrid extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double maxColumnWidth;
  final double spacing;

  const MasonryGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.maxColumnWidth = 260,
    this.spacing = 10,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / maxColumnWidth).ceil().clamp(1, 12);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) SizedBox(width: spacing),
              Expanded(
                child: Column(
                  children: [
                    for (var i = c; i < itemCount; i += columns)
                      Padding(
                        padding: EdgeInsets.only(bottom: spacing),
                        child: itemBuilder(context, i),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
