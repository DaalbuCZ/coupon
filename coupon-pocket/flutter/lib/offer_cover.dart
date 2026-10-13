import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'pictures.dart';
import 'artwork.dart';

/// Extend the artwork's top-edge colour behind the system bar and back button.
class OfferCover extends StatefulWidget {
  final String url;
  final double topInset;
  final Alignment alignment;
  final double rightInset;
  final bool trimEdge;
  const OfferCover({
    super.key,
    required this.url,
    required this.topInset,
    this.alignment = Alignment.center,
    this.rightInset = 0,
    this.trimEdge = false,
  });
  @override
  State<OfferCover> createState() => _OfferCoverState();
}

class _OfferCoverState extends State<OfferCover> {
  late var artwork = load();
  Future<({Uint8List bytes, Color background, Color rightBackground})?>
  load() async {
    final bytes = await picture(widget.url);
    if (bytes == null) return null;
    var background = Colors.transparent;
    var rightBackground = Colors.transparent;
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 16,
        targetHeight: 16,
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final pixels = await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (pixels != null) {
            Color sample(bool right) {
              final red = <int>[], green = <int>[], blue = <int>[];
              final horizontal = widget.rightInset > 0;
              final count = horizontal ? frame.image.height : frame.image.width;
              for (var i = 0; i < count; i++) {
                final offset = horizontal
                    ? (i * frame.image.width +
                              (right ? frame.image.width - 1 : 0)) *
                          4
                    : i * 4;
                if (pixels.getUint8(offset + 3) < 200) continue;
                red.add(pixels.getUint8(offset));
                green.add(pixels.getUint8(offset + 1));
                blue.add(pixels.getUint8(offset + 2));
              }
              if (red.isEmpty) return Colors.transparent;
              red.sort();
              green.sort();
              blue.sort();
              final middle = red.length ~/ 2;
              return Color.fromARGB(
                255,
                red[middle],
                green[middle],
                blue[middle],
              );
            }

            background = sample(false);
            rightBackground = widget.rightInset > 0 ? sample(true) : background;
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // Retain the image even if its small colour sample is unavailable.
    }
    return (
      bytes: bytes,
      background: background,
      rightBackground: rightBackground,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: artwork,
    builder: (context, snapshot) {
      final data = snapshot.data;
      if (data == null) {
        return Center(
          child: snapshot.connectionState != ConnectionState.done
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: 'Retry image',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => setState(() => artwork = load()),
                ),
        );
      }
      return ColoredBox(
        color: data.rightBackground == Colors.transparent
            ? Theme.of(context).colorScheme.surface
            : data.rightBackground,
        child: Padding(
          padding: EdgeInsets.only(
            top: widget.topInset,
            right: widget.rightInset,
          ),
          child: ColoredBox(
            color: data.background == Colors.transparent
                ? Theme.of(context).colorScheme.surface
                : data.background,
            child: Artwork(
              bytes: data.bytes,
              trimEdge: widget.trimEdge,
              alignment: widget.alignment,
            ),
          ),
        ),
      );
    },
  );
}
