import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps routes, dialogs and their MediaQuery in the same desktop viewport.
class AppViewport extends StatelessWidget {
  const AppViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF0F3F8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: LayoutBuilder(
            builder: (context, constraints) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: Size(constraints.maxWidth, constraints.maxHeight),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact menu rows that add columns instead of growing vertically on desktop.
class ResponsiveMenuGrid extends StatelessWidget {
  const ResponsiveMenuGrid({
    super.key,
    required this.children,
    this.spacing = 18,
    this.maxTileHeight = 200,
    this.minTileHeight = 170,
    this.aspectRatio = 1,
  });

  final List<Widget> children;
  final double spacing;
  final double maxTileHeight;
  final double minTileHeight;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = math.max(
          2,
          ((constraints.maxWidth + spacing) / (220 + spacing)).floor(),
        );
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio:
              width / (width / aspectRatio).clamp(minTileHeight, maxTileHeight),
          children: children,
        );
      },
    );
  }
}
