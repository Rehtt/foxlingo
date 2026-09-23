import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/image_translation_models.dart';

class CroppedImageRegion {
  const CroppedImageRegion({required this.bytes, required this.normalizedRect});

  final Uint8List bytes;
  final Rect normalizedRect;
}

Future<CroppedImageRegion> cropImageToRegion(
  Uint8List imageBytes,
  Rect normalizedRect,
) async {
  final codec = await ui.instantiateImageCodec(imageBytes);
  ui.Image? source;
  ui.Picture? picture;
  ui.Image? cropped;
  try {
    source = (await codec.getNextFrame()).image;
    final left = (normalizedRect.left * source.width).floor().clamp(
      0,
      source.width - 1,
    );
    final top = (normalizedRect.top * source.height).floor().clamp(
      0,
      source.height - 1,
    );
    final right = (normalizedRect.right * source.width).ceil().clamp(
      left + 1,
      source.width,
    );
    final bottom = (normalizedRect.bottom * source.height).ceil().clamp(
      top + 1,
      source.height,
    );
    final width = right - left;
    final height = bottom - top;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      source,
      Rect.fromLTRB(
        left.toDouble(),
        top.toDouble(),
        right.toDouble(),
        bottom.toDouble(),
      ),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    picture = recorder.endRecording();
    cropped = await picture.toImage(width, height);
    final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Unable to encode the selected screen region.');
    }
    return CroppedImageRegion(
      bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      normalizedRect: Rect.fromLTRB(
        left / source.width,
        top / source.height,
        right / source.width,
        bottom / source.height,
      ),
    );
  } finally {
    source?.dispose();
    picture?.dispose();
    cropped?.dispose();
    codec.dispose();
  }
}

ImageTranslationResult mapImageTranslationResultToRegion({
  required ImageTranslationResult result,
  required Rect normalizedRegion,
  required Size fullImageSize,
}) {
  final mapped = <ImageTextRegion>[];
  for (final region in result.regions) {
    final local = region.normalizedRect;
    final left = (normalizedRegion.left + local.left * normalizedRegion.width)
        .clamp(normalizedRegion.left, normalizedRegion.right);
    final top = (normalizedRegion.top + local.top * normalizedRegion.height)
        .clamp(normalizedRegion.top, normalizedRegion.bottom);
    final right = (normalizedRegion.left + local.right * normalizedRegion.width)
        .clamp(normalizedRegion.left, normalizedRegion.right);
    final bottom =
        (normalizedRegion.top + local.bottom * normalizedRegion.height).clamp(
          normalizedRegion.top,
          normalizedRegion.bottom,
        );
    if (right <= left || bottom <= top) {
      continue;
    }
    mapped.add(
      ImageTextRegion(
        normalizedRect: Rect.fromLTRB(left, top, right, bottom),
        sourceText: region.sourceText,
        translatedText: region.translatedText,
      ),
    );
  }
  return ImageTranslationResult(imageSize: fullImageSize, regions: mapped);
}
