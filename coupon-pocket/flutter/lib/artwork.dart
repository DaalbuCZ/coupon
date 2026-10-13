import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Bounded artwork decode; trim the thin frame supplied on online artwork.
class Artwork extends StatefulWidget {
  final Uint8List bytes;
  final bool trimEdge;
  final Alignment alignment;
  const Artwork({
    super.key,
    required this.bytes,
    this.trimEdge = false,
    this.alignment = Alignment.center,
  });
  @override
  State<Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends State<Artwork> {
  ImageStream? stream;
  ImageInfo? info;
  late final listener = ImageStreamListener((value, _) {
    final old = info;
    setState(() => info = value);
    old?.dispose();
  });
  void resolve() {
    stream?.removeListener(listener);
    stream = ResizeImage(
      MemoryImage(widget.bytes),
      width: 600,
      height: 600,
      policy: ResizeImagePolicy.fit,
    ).resolve(createLocalImageConfiguration(context));
    stream!.addListener(listener);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    resolve();
  }

  @override
  void didUpdateWidget(Artwork old) {
    super.didUpdateWidget(old);
    if (old.bytes != widget.bytes) resolve();
  }

  @override
  void dispose() {
    stream?.removeListener(listener);
    info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ArtworkPainter(info?.image, widget.trimEdge, widget.alignment),
    size: Size.infinite,
  );
}

class _ArtworkPainter extends CustomPainter {
  final ui.Image? image;
  final bool trim;
  final Alignment alignment;
  _ArtworkPainter(this.image, this.trim, this.alignment);
  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image == null) return;
    final edge = trim && image.width > 2 && image.height > 2 ? 1.0 : 0.0;
    final source = Rect.fromLTRB(
      edge,
      edge,
      image.width - edge,
      image.height - edge,
    );
    final fitted = applyBoxFit(BoxFit.contain, source.size, size);
    final destination = alignment.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_ArtworkPainter old) =>
      image != old.image || trim != old.trim || alignment != old.alignment;
}
