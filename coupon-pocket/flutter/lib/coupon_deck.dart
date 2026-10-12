import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A lazy Rolodex stack with continuous native scrolling and fixed paint order.
class CouponDeck extends StatefulWidget {
  final int count;
  final String Function(int) identity;
  final Widget Function(int) builder;
  const CouponDeck({
    super.key,
    required this.count,
    required this.identity,
    required this.builder,
  });
  @override
  State<CouponDeck> createState() => _CouponDeckState();
}

class _CouponDeckState extends State<CouponDeck> {
  final controller = ScrollController();
  Drag? drag;
  int current = 0;
  double stride = 240;
  final cards = <int, Widget>{};

  @override
  void initState() {
    super.initState();
    controller.addListener(updateFocus);
  }

  void updateFocus() {
    final next = (controller.offset / stride).round().clamp(
      0,
      widget.count - 1,
    );
    if (next != current && mounted) setState(() => current = next);
  }

  @override
  void didUpdateWidget(CouponDeck old) {
    super.didUpdateWidget(old);
    cards.clear();
    if (old.count != widget.count) {
      current = current.clamp(0, math.max(0, widget.count - 1));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) {
          controller.jumpTo(
            controller.offset.clamp(0, math.max(0, widget.count - 1) * stride),
          );
        }
      });
    }
  }

  void focus(int index) {
    controller.animateTo(
      index.clamp(0, widget.count - 1) * stride,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    drag?.cancel();
    controller.removeListener(updateFocus);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, area) {
      final side = math.min(area.maxWidth - 24, area.maxHeight * .85);
      stride = side * .78;
      final centerTop = (area.maxHeight - side) / 2;
      cards.removeWhere((i, _) => i < current - 3 || i > current + 3);
      final nearby = {
        for (
          var i = math.max(0, current - 2);
          i <= math.min(widget.count - 1, current + 2);
          i++
        )
          i: RepaintBoundary(
            key: ValueKey(widget.identity(i)),
            child: cards.putIfAbsent(i, () => widget.builder(i)),
          ),
      };
      return Semantics(
        label: 'Coupon stack',
        onIncrease: current < widget.count - 1
            ? () => focus(current + 1)
            : null,
        onDecrease: current > 0 ? () => focus(current - 1) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (details) {
            drag = controller.position.drag(details, () => drag = null);
          },
          onVerticalDragUpdate: (details) => drag?.update(details),
          onVerticalDragEnd: (details) => drag?.end(details),
          onVerticalDragCancel: () => drag?.cancel(),
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                controller.jumpTo(
                  (controller.offset + event.scrollDelta.dy).clamp(
                    0,
                    controller.position.maxScrollExtent,
                  ),
                );
              }
            },
            child: ClipRect(
              child: Stack(
                children: [
                  // Supplies native fling friction, overscroll notifications and bounds.
                  // Its pixels map 1:1 to the visible card translation; there is no snap.
                  IgnorePointer(
                    child: ListView.builder(
                      controller: controller,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: GentleFlickPhysics(),
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: (area.maxHeight - stride) / 2,
                      ),
                      itemExtent: stride,
                      itemCount: widget.count,
                      itemBuilder: (_, _) => const SizedBox.expand(),
                    ),
                  ),
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) {
                        final position = controller.hasClients
                            ? (controller.offset / stride).clamp(
                                0.0,
                                math.max(0, widget.count - 1).toDouble(),
                              )
                            : current.toDouble();
                        return Stack(
                          children: [
                            // Increasing indices paint last: lower cards always sit in front.
                            for (final i in nearby.keys)
                              Positioned(
                                key: ValueKey(widget.identity(i)),
                                width: side,
                                height: side,
                                left: (area.maxWidth - side) / 2,
                                top: centerTop,
                                child: Transform(
                                  alignment: Alignment.topCenter,
                                  transform: cardTransform(
                                    i - position,
                                    side,
                                    stride,
                                  ),
                                  child: nearby[i],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 40,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Theme.of(context).scaffoldBackgroundColor,
                              Theme.of(context).scaffoldBackgroundColor
                                  .withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Matrix4 cardTransform(double relative, double side, double spacing) {
    final progress = relative.clamp(0.0, 1.0);
    final fold = progress * progress * (3 - 2 * progress);
    // Keep the next card's hinge below the flat card's bottom. As it approaches
    // the lower edge it folds toward horizontal, revealing the whole card above.
    final slide = relative * spacing + fold * (side - spacing + 24);
    final rear = (-relative).clamp(0.0, 1.0);
    final scale = 1 - rear * .12;
    final angle = relative < 0
        ? -rear * rear * (3 - 2 * rear) * .22
        : fold * 1.08;
    return Matrix4.identity()
      ..setEntry(3, 2, .0007)
      ..translateByDouble(0, slide, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..rotateX(angle);
  }
}

class GentleFlickPhysics extends ClampingScrollPhysics {
  const GentleFlickPhysics({super.parent});
  @override
  GentleFlickPhysics applyTo(ScrollPhysics? ancestor) =>
      GentleFlickPhysics(parent: buildParent(ancestor));
  @override
  double get maxFlingVelocity => 2600;
  @override
  double get minFlingVelocity => 300;
  @override
  double get minFlingDistance => 24;
  @override
  double carriedMomentum(double existingVelocity) => 0;
  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => super.createBallisticSimulation(
    position,
    velocity.abs() < minFlingVelocity ? 0 : velocity * .55,
  );
}
