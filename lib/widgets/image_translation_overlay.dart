import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/image_translation_models.dart';

const double _cjkInkCompensation = 0.85;
const double _lineHeightRatio = 1.2;
const double _paddingYRatio = 0.08;
const double _paddingXRatio = 0.10;
const double _radiusRatio = 0.08;
const double _maxPaddingFraction = 0.2;

const TextStyle _translationTextStyle = TextStyle(
  color: Colors.white,
  fontWeight: FontWeight.w600,
  height: _lineHeightRatio,
  shadows: [Shadow(color: Colors.black, blurRadius: 1)],
);

class ImageTranslationOverlay extends StatelessWidget {
  const ImageTranslationOverlay({super.key, required this.result});

  final ImageTranslationResult result;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final imageRect = containedImageRect(
            viewport: viewport,
            imageAspectRatio: result.imageAspectRatio,
          );
          if (imageRect.isEmpty ||
              result.regions.isEmpty ||
              !_isPositiveSize(result.imageSize)) {
            return const SizedBox.expand();
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final region in result.regions)
                _buildRegion(
                  imageRect: imageRect,
                  imageSize: result.imageSize,
                  region: region,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRegion({
    required Rect imageRect,
    required Size imageSize,
    required ImageTextRegion region,
  }) {
    final imageBox = imageSpaceRect(
      imageSize: imageSize,
      normalizedRect: region.normalizedRect,
    );
    final screenRect = screenSpaceRect(
      imageRect: imageRect,
      normalizedRect: region.normalizedRect,
    );
    if (!_isPositiveSize(imageBox.size) || !_isPositiveSize(screenRect.size)) {
      return const SizedBox.shrink();
    }

    final padding = imageSpacePadding(imageBox.size);
    final available = Size(
      math.max(0, imageBox.width - padding.horizontal),
      math.max(0, imageBox.height - padding.vertical),
    );
    if (!_isPositiveSize(available)) {
      return const SizedBox.shrink();
    }

    final fontSize = estimateSourceFontSize(
      sourceText: region.sourceText,
      boxSize: available,
    ) * _cjkInkCompensation;

    return Positioned.fromRect(
      rect: screenRect,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: imageBox.width,
          height: imageBox.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              imageBox.height * _radiusRatio,
            ),
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.74),
              child: Padding(
                padding: padding,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: available.width,
                    child: Text(
                      region.translatedText,
                      textAlign: TextAlign.center,
                      style: _translationTextStyle.copyWith(fontSize: fontSize),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Rect containedImageRect({
  required Size viewport,
  required double imageAspectRatio,
}) {
  if (viewport.width <= 0 ||
      viewport.height <= 0 ||
      !imageAspectRatio.isFinite ||
      imageAspectRatio <= 0) {
    return Rect.zero;
  }

  final fitted = applyBoxFit(
    BoxFit.contain,
    Size(imageAspectRatio, 1),
    viewport,
  );
  final destination = fitted.destination;
  return Alignment.center.inscribe(destination, Offset.zero & viewport);
}

@visibleForTesting
Rect imageSpaceRect({
  required Size imageSize,
  required Rect normalizedRect,
}) {
  return Rect.fromLTRB(
    normalizedRect.left * imageSize.width,
    normalizedRect.top * imageSize.height,
    normalizedRect.right * imageSize.width,
    normalizedRect.bottom * imageSize.height,
  );
}

@visibleForTesting
Rect screenSpaceRect({
  required Rect imageRect,
  required Rect normalizedRect,
}) {
  return Rect.fromLTRB(
    imageRect.left + normalizedRect.left * imageRect.width,
    imageRect.top + normalizedRect.top * imageRect.height,
    imageRect.left + normalizedRect.right * imageRect.width,
    imageRect.top + normalizedRect.bottom * imageRect.height,
  ).intersect(imageRect);
}

@visibleForTesting
EdgeInsets imageSpacePadding(Size boxSize) {
  var padY = boxSize.height * _paddingYRatio;
  var padX = boxSize.height * _paddingXRatio;
  if (padY * 2 >= boxSize.height) {
    padY = boxSize.height * _maxPaddingFraction;
  }
  if (padX * 2 >= boxSize.width) {
    padX = boxSize.width * _maxPaddingFraction;
  }
  return EdgeInsets.symmetric(horizontal: padX, vertical: padY);
}

@visibleForTesting
double estimateSourceFontSize({
  required String sourceText,
  required Size boxSize,
  double lineHeightRatio = _lineHeightRatio,
}) {
  if (!_isPositiveSize(boxSize)) {
    return 0;
  }

  final heightCap = boxSize.height / lineHeightRatio;
  final advanceUnits = _advanceUnitsFor(sourceText);
  if (advanceUnits <= 0) {
    return heightCap;
  }

  final estimated = math.sqrt(
    boxSize.width * boxSize.height / (advanceUnits * lineHeightRatio),
  );
  return math.min(estimated, heightCap);
}

bool _isPositiveSize(Size size) {
  return size.width > 0 &&
      size.height > 0 &&
      size.width.isFinite &&
      size.height.isFinite;
}

double _advanceUnitsFor(String text) {
  var units = 0.0;
  for (final rune in text.runes) {
    if (_isWhitespace(rune)) {
      units += 0.3;
    } else if (_isCjkOrFullwidth(rune)) {
      units += 1.0;
    } else if (rune > 0x20) {
      units += 0.5;
    }
  }
  return units;
}

bool _isWhitespace(int rune) {
  return rune == 0x09 ||
      rune == 0x0A ||
      rune == 0x0D ||
      rune == 0x20 ||
      rune == 0x00A0 ||
      rune == 0x3000;
}

bool _isCjkOrFullwidth(int rune) {
  return (rune >= 0x2E80 && rune <= 0x2EFF) ||
      (rune >= 0x2F00 && rune <= 0x2FDF) ||
      (rune >= 0x3001 && rune <= 0x303F) ||
      (rune >= 0x3040 && rune <= 0x30FF) ||
      (rune >= 0x3100 && rune <= 0x312F) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xAC00 && rune <= 0xD7AF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0xFF01 && rune <= 0xFF60) ||
      (rune >= 0xFFE0 && rune <= 0xFFE6) ||
      (rune >= 0x20000 && rune <= 0x2A6DF);
}
