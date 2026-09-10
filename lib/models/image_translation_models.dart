import 'dart:ui';

class ImageTextRegion {
  const ImageTextRegion({
    required this.normalizedRect,
    required this.sourceText,
    required this.translatedText,
  });

  final Rect normalizedRect;
  final String sourceText;
  final String translatedText;

  Map<String, dynamic> toJson() {
    return {
      'normalizedRect': <double>[
        normalizedRect.left,
        normalizedRect.top,
        normalizedRect.right,
        normalizedRect.bottom,
      ],
      'sourceText': sourceText,
      'translatedText': translatedText,
    };
  }

  factory ImageTextRegion.fromJson(Map<String, dynamic> json) {
    final rect = json['normalizedRect'];
    if (rect is! List || rect.length != 4) {
      throw const FormatException('normalizedRect must be [left, top, right, bottom].');
    }
    final coordinates = <double>[];
    for (final value in rect) {
      if (value is! num || !value.isFinite) {
        throw const FormatException('normalizedRect values must be finite numbers.');
      }
      coordinates.add(value.toDouble());
    }
    return ImageTextRegion(
      normalizedRect: Rect.fromLTRB(
        coordinates[0],
        coordinates[1],
        coordinates[2],
        coordinates[3],
      ),
      sourceText: json['sourceText'] as String? ?? '',
      translatedText: json['translatedText'] as String? ?? '',
    );
  }
}

class ImageTranslationResult {
  const ImageTranslationResult({
    required this.imageSize,
    required this.regions,
  });

  final Size imageSize;
  final List<ImageTextRegion> regions;

  double get imageAspectRatio => imageSize.width / imageSize.height;

  Map<String, dynamic> toJson() {
    return {
      'imageSize': <double>[imageSize.width, imageSize.height],
      'regions': regions.map((region) => region.toJson()).toList(),
    };
  }

  factory ImageTranslationResult.fromJson(Map<String, dynamic> json) {
    final size = json['imageSize'];
    if (size is! List || size.length != 2) {
      throw const FormatException('imageSize must be [width, height].');
    }
    final width = size[0];
    final height = size[1];
    if (width is! num || height is! num || !width.isFinite || !height.isFinite) {
      throw const FormatException('imageSize values must be finite numbers.');
    }

    final regionsJson = json['regions'];
    if (regionsJson is! List) {
      throw const FormatException('regions must be a list.');
    }

    return ImageTranslationResult(
      imageSize: Size(width.toDouble(), height.toDouble()),
      regions: [
        for (final entry in regionsJson)
          ImageTextRegion.fromJson(Map<String, dynamic>.from(entry as Map)),
      ],
    );
  }
}
