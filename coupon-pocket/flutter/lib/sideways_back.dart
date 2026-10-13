import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;

/// A horizontal route transition driven by Android's cancellable back gesture.
class SidewaysBackTransitionsBuilder extends PageTransitionsBuilder {
  const SidewaysBackTransitionsBuilder();
  @override
  Duration get transitionDuration => const Duration(milliseconds: 190);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 170);
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _SidewaysBack(
    route: route,
    animation: animation,
    secondary: secondaryAnimation,
    child: child,
  );
}

class _SidewaysBack extends StatefulWidget {
  final PageRoute<dynamic> route;
  final Animation<double> animation, secondary;
  final Widget child;
  const _SidewaysBack({
    required this.route,
    required this.animation,
    required this.secondary,
    required this.child,
  });
  @override
  State<_SidewaysBack> createState() => _SidewaysBackState();
}

class _SidewaysBackState extends State<_SidewaysBack>
    with WidgetsBindingObserver {
  double lastProgress = 0;
  double? commitProgress;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    final navigator = widget.route.navigator;
    if (navigator == null ||
        ModalRoute.of(navigator.context)?.isCurrent == false)
      return false;
    if (event.isButtonEvent ||
        !widget.route.isCurrent ||
        !widget.route.popGestureEnabled) {
      return false;
    }
    lastProgress = event.progress;
    commitProgress = null;
    widget.route.handleStartBackGesture(progress: 1 - event.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) {
    lastProgress = event.progress;
    widget.route.handleUpdateBackGestureProgress(progress: 1 - event.progress);
  }

  @override
  void handleCancelBackGesture() => widget.route.handleCancelBackGesture();
  @override
  void handleCommitBackGesture() {
    commitProgress = lastProgress;
    widget.route.handleCommitBackGesture();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final direction = Directionality.of(context) == TextDirection.ltr
        ? 1.0
        : -1.0;
    return AnimatedBuilder(
      animation: Listenable.merge([widget.animation, widget.secondary]),
      child: widget.child,
      builder: (context, child) {
        final primary = widget.route.popGestureInProgress
            ? (1 - (commitProgress ?? 0)) * widget.animation.value
            : Curves.easeOutCubic.transform(widget.animation.value);
        final secondary = widget.route.navigator?.userGestureInProgress == true
            ? widget.secondary.value
            : Curves.easeOutCubic.transform(widget.secondary.value);
        return FractionalTranslation(
          translation: Offset(direction * ((1 - primary) - .18 * secondary), 0),
          child: child,
        );
      },
    );
  }
}
