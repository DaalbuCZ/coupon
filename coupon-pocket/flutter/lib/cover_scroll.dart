import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// The content sheet moves over the cover; its title remains pinned at the top.
class CoverScroll extends StatelessWidget {
  final String title;
  final Widget cover, content;
  final VoidCallback onBack;
  final Widget? titleAction;
  final double coverHeight;
  final bool parallax;
  const CoverScroll({
    super.key,
    required this.title,
    required this.cover,
    required this.content,
    required this.onBack,
    this.titleAction,
    this.coverHeight = 320,
    this.parallax = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.headlineMedium!.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.15,
    );
    final painter =
        TextPainter(
          text: TextSpan(text: title, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 3,
        )..layout(
          maxWidth:
              MediaQuery.sizeOf(context).width -
              40 -
              (titleAction == null ? 0 : 52),
        );
    final titleHeight =
        (titleAction != null && painter.height < 48 ? 48.0 : painter.height) +
        40;
    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _CoverHeader(
            title: title,
            style: style,
            cover: cover,
            onBack: onBack,
            action: titleAction,
            titleHeight: titleHeight,
            coverHeight: coverHeight,
            top: MediaQuery.paddingOf(context).top,
            surface: theme.colorScheme.surface,
            parallax: parallax && !MediaQuery.disableAnimationsOf(context),
          ),
        ),
        SliverToBoxAdapter(
          child: ColoredBox(
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: content,
            ),
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: ColoredBox(color: theme.colorScheme.surface),
        ),
      ],
    );
  }
}

class _CoverHeader extends SliverPersistentHeaderDelegate {
  final String title;
  final TextStyle style;
  final Widget cover;
  final Widget? action;
  final VoidCallback onBack;
  final double top, titleHeight, coverHeight;
  final Color surface;
  final bool parallax;
  _CoverHeader({
    required this.title,
    required this.style,
    required this.cover,
    required this.onBack,
    required this.action,
    required this.titleHeight,
    required this.coverHeight,
    required this.top,
    required this.surface,
    required this.parallax,
  });
  @override
  double get minExtent => top + 64;
  @override
  double get maxExtent => coverHeight + titleHeight - 24;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final sheetHeight = lerpDouble(titleHeight, minExtent, progress)!;
    final fontSize = lerpDouble(style.fontSize, 22, progress)!;
    final textTop = lerpDouble(20, top + (64 - fontSize * 1.15) / 2, progress)!;
    final radius = 28 * (1 - progress);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: surface),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: coverHeight,
            child: Transform.translate(
              offset: Offset(
                0,
                parallax
                    ? -shrinkOffset.clamp(0.0, maxExtent - minExtent) * .25
                    : 0,
              ),
              child: RepaintBoundary(child: cover),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: sheetHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(radius),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  left: lerpDouble(20, 64, progress)!,
                  right: 20,
                  top: textTop,
                  bottom: progress < .95 ? 20 : 0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: style.copyWith(fontSize: fontSize),
                        maxLines: progress > .95 ? 1 : 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (action != null)
                      SizedBox(height: fontSize * 1.15, child: action),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: top + 8,
            left: 8,
            width: 48,
            height: 48,
            child: Material(
              color: surface.withValues(alpha: lerpDouble(.85, 1, progress)!),
              shape: const CircleBorder(),
              child: BackButton(onPressed: onBack),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_CoverHeader old) =>
      title != old.title ||
      style != old.style ||
      cover != old.cover ||
      surface != old.surface ||
      action != old.action ||
      titleHeight != old.titleHeight ||
      coverHeight != old.coverHeight ||
      top != old.top ||
      parallax != old.parallax;
}
