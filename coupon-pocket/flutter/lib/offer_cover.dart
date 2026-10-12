import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'pictures.dart';

/// Extend the artwork's top-edge colour behind the system bar and back button.
class OfferCover extends StatefulWidget {
  final String url;
  final double topInset;
  const OfferCover({super.key, required this.url, required this.topInset});
  @override
  State<OfferCover> createState() => _OfferCoverState();
}

class _OfferCoverState extends State<OfferCover> {
  late var artwork = load();
  Future<({Uint8List bytes, Color background})?> load() async {
    final bytes = await picture(widget.url);
    if (bytes == null) return null;
    var background = Colors.transparent;
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
            final red = <int>[], green = <int>[], blue = <int>[];
            for (var x = 0; x < frame.image.width; x++) {
              final offset = x * 4;
              if (pixels.getUint8(offset + 3) < 200) continue;
              red.add(pixels.getUint8(offset));
              green.add(pixels.getUint8(offset + 1));
              blue.add(pixels.getUint8(offset + 2));
            }
            if (red.isNotEmpty) {
              red.sort();
              green.sort();
              blue.sort();
              final middle = red.length ~/ 2;
              background = Color.fromARGB(
                255,
                red[middle],
                green[middle],
                blue[middle],
              );
            }
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
    return (bytes: bytes, background: background);
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
        color: data.background == Colors.transparent
            ? Theme.of(context).colorScheme.surface
            : data.background,
        child: Padding(
          padding: EdgeInsets.only(top: widget.topInset),
          child: Image.memory(data.bytes, fit: BoxFit.contain, cacheWidth: 600),
        ),
      );
    },
  );
}
