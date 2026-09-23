import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../l10n/app_localizations.dart';
import '../models/image_translation_models.dart';
import '../platform/overlay_controller.dart';
import '../platform/translation_bridge.dart';
import 'image_translation_overlay.dart';

class TranslationOverlayApp extends StatefulWidget {
  const TranslationOverlayApp({super.key, required this.bridge});

  final TranslationBridge bridge;

  @override
  State<TranslationOverlayApp> createState() => _TranslationOverlayAppState();
}

class _TranslationOverlayAppState extends State<TranslationOverlayApp> {
  _OverlayState _overlayState = const _OverlayState();
  StreamSubscription<TranslationBridgeMessage>? _subscription;
  Timer? _readyTimer;
  bool _sentReady = false;
  Size? _displaySize;
  bool? _fullScreen;
  Future<void> _windowOperation = Future<void>.value();
  MemoryImage? _frameImage;
  OverlayPosition? _bubblePosition;
  int _preparationGeneration = 0;
  String? _lastClosedRequestId;
  bool _menuOpen = false;
  OverlayPosition? _menuAnchor;
  int _menuGeneration = 0;

  @override
  void initState() {
    super.initState();
    _subscription = widget.bridge.messages.listen(_onMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendReady();
      _readyTimer = Timer.periodic(
        const Duration(milliseconds: 300),
        (_) => _sendReady(),
      );
    });
  }

  void _sendReady() {
    if (_sentReady && _overlayState.sessionId != null) {
      _readyTimer?.cancel();
      return;
    }
    unawaited(
      widget.bridge.send(const <String, dynamic>{
        'version': 1,
        'type': 'ready',
      }),
    );
    _sentReady = true;
  }

  void _onMessage(TranslationBridgeMessage message) {
    if (message['version'] != 1) {
      return;
    }
    final type = message['type'];
    if (type is! String) {
      return;
    }
    final sessionId = message['sessionId'];
    if (type == 'handshake') {
      _handleHandshake(sessionId);
      return;
    }
    final currentSession = _overlayState.sessionId;
    if (type != 'state' &&
        type != 'stopped' &&
        currentSession != null &&
        sessionId != currentSession) {
      return;
    }
    const requestScopedTypes = <String>{
      'prepareCapture',
      'capturedFrame',
      'progress',
      'result',
      'error',
    };
    if (requestScopedTypes.contains(type)) {
      final currentRequest = _overlayState.requestId;
      if (sessionId != currentSession ||
          message['requestId'] is! String ||
          currentRequest == null ||
          message['requestId'] != currentRequest) {
        return;
      }
    }

    final payload = message['payload'];
    final data = payload is Map
        ? Map<String, dynamic>.from(payload)
        : const <String, dynamic>{};
    switch (type) {
      case 'state':
        _applyState(
          sessionId is String ? sessionId : null,
          data,
          message['requestId'],
        );
      case 'prepareCapture':
        unawaited(
          _prepareCapture(
            sessionId is String ? sessionId : null,
            message['requestId'],
          ),
        );
      case 'capturedFrame':
        _applyFrame(data);
      case 'progress':
        _applyProgress(data);
      case 'result':
        _applyResult(data);
      case 'error':
        _applyError(data);
      case 'stopped':
        _clearOverlay();
    }
  }

  void _handleHandshake(Object? rawSessionId) {
    if (rawSessionId is! String || rawSessionId.isEmpty) {
      return;
    }
    _preparationGeneration++;
    _evictFrameImage();
    _bubblePosition = null;
    _fullScreen = null;
    _lastClosedRequestId = null;
    _resetMenu();
    if (mounted) {
      setState(() {
        _overlayState = _OverlayState(
          sessionId: rawSessionId,
          state: 'starting',
        );
      });
    }
    _readyTimer?.cancel();
    _sentReady = true;
    unawaited(_setClickThrough(false));
    unawaited(_setWindowMode(false, force: true));
    unawaited(
      widget.bridge.send(<String, dynamic>{
        'version': 1,
        'type': 'ready',
        'sessionId': rawSessionId,
      }),
    );
  }

  void _applyState(
    String? sessionId,
    Map<String, dynamic> data,
    Object? rawRequestId,
  ) {
    final nextState = data['state'];
    if (sessionId == null || nextState is! String) {
      return;
    }
    final nextRequestId = rawRequestId is String ? rawRequestId : null;
    final resetTask = nextState == 'ready' || nextState == 'stopped';
    final endPreparation = resetTask || nextState == 'error';
    if (!resetTask &&
        nextRequestId != null &&
        _overlayState.state == 'ready' &&
        _lastClosedRequestId == nextRequestId) {
      return;
    }
    if (endPreparation) {
      _preparationGeneration++;
      unawaited(_setClickThrough(false));
    }
    if (resetTask) {
      if (_overlayState.requestId != null) {
        _lastClosedRequestId = _overlayState.requestId;
      }
      _evictFrameImage();
    }
    setState(() {
      _resetMenu();
      _overlayState = _overlayState.copyWith(
        sessionId: sessionId,
        requestId: nextRequestId,
        state: nextState,
        translationMode: data['translationMode'] == 'region'
            ? 'region'
            : data['translationMode'] == 'fullScreen'
            ? 'fullScreen'
            : _overlayState.translationMode,
        hasSelectedRegion: data['hasSelectedRegion'] == true,
        locale: data['locale'] is String
            ? data['locale'] as String
            : _overlayState.locale,
        errorCode: data['errorCode'] is String
            ? data['errorCode'] as String
            : null,
        errorMessage: data['errorMessage'] is String
            ? data['errorMessage'] as String
            : null,
        frameWidth: _asInt(data['frameWidth']),
        frameHeight: _asInt(data['frameHeight']),
        preparing: endPreparation ? false : _overlayState.preparing,
        clearProgress: endPreparation,
        clearRequest: resetTask || nextRequestId == null,
        clearError: true,
      );
      if (resetTask) {
        _overlayState = _overlayState.copyWith(
          clearFrame: true,
          clearResult: true,
          clearProgress: true,
          clearError: true,
        );
      }
    });
    unawaited(_setWindowMode(_needsFullScreen(nextState), force: resetTask));
  }

  Future<void> _prepareCapture(String? sessionId, Object? requestId) async {
    if (sessionId == null || requestId is! String) {
      return;
    }
    final preparationGeneration = ++_preparationGeneration;
    _evictFrameImage();
    if (!mounted) {
      return;
    }
    setState(() {
      _resetMenu();
      _overlayState = _overlayState.copyWith(
        sessionId: sessionId,
        requestId: requestId,
        clearFrame: true,
        clearResult: true,
        preparing: true,
        clearProgress: true,
        clearError: true,
      );
    });
    await _setClickThrough(true);
    if (!mounted ||
        preparationGeneration != _preparationGeneration ||
        _overlayState.sessionId != sessionId ||
        _overlayState.requestId != requestId ||
        !_overlayState.preparing) {
      await _setClickThrough(false);
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        preparationGeneration != _preparationGeneration ||
        _overlayState.sessionId != sessionId ||
        _overlayState.requestId != requestId ||
        !_overlayState.preparing) {
      await _setClickThrough(false);
      return;
    }
    await widget.bridge.send(<String, dynamic>{
      'version': 1,
      'type': 'capturePrepared',
      'sessionId': sessionId,
      'requestId': requestId,
    });
  }

  void _applyFrame(Map<String, dynamic> data) {
    final bytes = data['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      return;
    }
    _evictFrameImage();
    _frameImage = MemoryImage(bytes);
    setState(() {
      _overlayState = _overlayState.copyWith(
        frameBytes: bytes,
        frameWidth: _asInt(data['width']),
        frameHeight: _asInt(data['height']),
        preparing: false,
      );
    });
    unawaited(_setClickThrough(false));
  }

  void _applyProgress(Map<String, dynamic> data) {
    if (!mounted) {
      return;
    }
    setState(() {
      final stage = data['stage'] is String ? data['stage'] as String : null;
      _overlayState = _overlayState.copyWith(
        progressStage: stage,
        progressRegionCount: _asInt(data['regionCount']),
        clearProgress: stage == null,
      );
    });
  }

  void _applyResult(Map<String, dynamic> data) {
    final rawResult = data['result'];
    if (rawResult is! Map) {
      return;
    }
    try {
      final result = ImageTranslationResult.fromJson(
        Map<String, dynamic>.from(rawResult),
      );
      setState(() {
        _overlayState = _overlayState.copyWith(
          state: 'result',
          result: result,
          preparing: false,
          clearProgress: true,
        );
      });
      unawaited(_setClickThrough(false));
      unawaited(_setWindowMode(true));
    } on Object {
      _applyError(<String, dynamic>{'message': 'Invalid translation result.'});
    }
  }

  void _applyError(Map<String, dynamic> data) {
    if (!mounted) {
      return;
    }
    setState(() {
      _overlayState = _overlayState.copyWith(
        state: 'error',
        errorCode: data['code'] is String ? data['code'] as String : null,
        errorMessage: data['message'] is String
            ? data['message'] as String
            : 'Translation failed.',
        preparing: false,
        clearProgress: true,
        clearError: true,
      );
    });
    unawaited(_setClickThrough(false));
    unawaited(_setWindowMode(true));
  }

  Future<void> _sendAction(String type, {Map<String, dynamic>? payload}) async {
    final sessionId = _overlayState.sessionId;
    if (sessionId == null) {
      return;
    }
    await widget.bridge.send(<String, dynamic>{
      'version': 1,
      'type': type,
      'sessionId': sessionId,
      'requestId': ?_overlayState.requestId,
      'payload': ?payload,
    });
  }

  Future<void> _sendSelectedRegion(Rect region) => _sendAction(
    'regionSelected',
    payload: <String, dynamic>{
      'rect': <double>[region.left, region.top, region.right, region.bottom],
    },
  );

  void _resetMenu() {
    _menuGeneration++;
    _menuOpen = false;
    _menuAnchor = null;
  }

  Future<void> _openMenu() async {
    if (_overlayState.preparing || _needsFullScreen(_overlayState.state)) {
      return;
    }
    if (_menuOpen && _menuAnchor != null) {
      return;
    }
    final generation = ++_menuGeneration;
    if (mounted) {
      setState(() {
        _menuOpen = true;
        _menuAnchor = null;
      });
    }
    await _setWindowMode(true);
    if (!mounted || generation != _menuGeneration || !_menuOpen) {
      return;
    }
    setState(() {
      _menuAnchor = _bubblePosition ?? const OverlayPosition(0, 0);
    });
  }

  Future<void> _closeMenu() async {
    if (!_menuOpen && _menuAnchor == null) {
      return;
    }
    _menuGeneration++;
    if (mounted) {
      setState(() {
        _menuOpen = false;
        _menuAnchor = null;
      });
    } else {
      _menuOpen = false;
      _menuAnchor = null;
    }
    if (_needsFullScreen(_overlayState.state) || _overlayState.preparing) {
      return;
    }
    await _setWindowMode(false);
  }

  Future<void> _onMenuAction(String type) async {
    await _closeMenu();
    switch (type) {
      case 'modeFullScreen':
        await _sendAction(
          'setTranslationMode',
          payload: const <String, dynamic>{'mode': 'fullScreen'},
        );
      case 'modeRegion':
        await _sendAction(
          'setTranslationMode',
          payload: const <String, dynamic>{'mode': 'region'},
        );
      default:
        await _sendAction(type);
    }
  }

  Future<void> _setWindowMode(bool fullScreen, {bool force = false}) {
    if (!force && _fullScreen == fullScreen) {
      return _windowOperation;
    }
    final enteringFullScreen = fullScreen && _fullScreen != true;
    final restoringBubble = !fullScreen && _fullScreen == true;
    _fullScreen = fullScreen;
    _windowOperation = _windowOperation.catchError((_) {}).then((_) async {
      try {
        final currentDisplaySize = await widget.bridge.displaySize();
        if (currentDisplaySize != null) {
          _displaySize = currentDisplaySize;
        }
        if (fullScreen) {
          try {
            if (enteringFullScreen) {
              _bubblePosition = await FlutterOverlayWindow.getOverlayPosition();
            }
          } on Object {
            // The overlay may not have reported a position during cold start.
          }
          final size = _displaySize;
          if (size != null) {
            await FlutterOverlayWindow.resizeOverlay(
              size.width.ceil(),
              size.height.ceil(),
              false,
            );
          }
          // With centerRight gravity (the plugin's showOverlay alignment),
          // zero x/y centers a full-screen window on the display.
          await FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 0));
          await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
        } else {
          await FlutterOverlayWindow.resizeOverlay(56, 56, true);
          await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
          await _clampBubblePosition(_displaySize, restore: restoringBubble);
        }
      } on Object {
        // A window operation can race with overlay startup or shutdown.
      }
    });
    return _windowOperation;
  }

  Future<void> _clampBubblePosition(
    Size? displaySize, {
    required bool restore,
  }) async {
    if (displaySize == null ||
        displaySize.width <= 0 ||
        displaySize.height <= 0) {
      return;
    }
    try {
      final position = restore && _bubblePosition != null
          ? _bubblePosition!
          : await FlutterOverlayWindow.getOverlayPosition();
      final clamped = OverlayPositioning.clampBubblePosition(
        position,
        displaySize,
      );
      _bubblePosition = clamped;
      await FlutterOverlayWindow.moveOverlay(clamped);
    } on Object {
      // The overlay may already be closing or not yet have a window manager.
    }
  }

  Future<void> _setClickThrough(bool clickThrough) async {
    try {
      await FlutterOverlayWindow.updateFlag(
        clickThrough ? OverlayFlag.clickThrough : OverlayFlag.defaultFlag,
      );
    } on MissingPluginException {
      // The native overlay plugin may not be ready during a cold handshake.
    }
  }

  bool _needsFullScreen(String state) {
    return state == 'selecting' ||
        state == 'translating' ||
        state == 'result' ||
        state == 'error';
  }

  void _clearOverlay() {
    _evictFrameImage();
    if (!mounted) {
      return;
    }
    setState(() {
      _resetMenu();
      _overlayState = const _OverlayState(state: 'stopped');
    });
  }

  void _evictFrameImage() {
    final oldImage = _frameImage;
    _frameImage = null;
    if (oldImage != null) {
      unawaited(oldImage.evict().then<void>((_) {}));
    }
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    _evictFrameImage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = _overlayState.locale == 'zh'
        ? const Locale('zh')
        : const Locale('en');
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2f6f73)),
        useMaterial3: true,
      ),
      home: _OverlaySurface(
        state: _overlayState,
        frameImage: _frameImage,
        menuOpen: _menuOpen,
        menuAnchor: _menuAnchor,
        onAction: (type) => _sendAction(type),
        onSelectRegion: _sendSelectedRegion,
        onOpenMenu: _openMenu,
        onCloseMenu: _closeMenu,
        onMenuAction: _onMenuAction,
      ),
    );
  }
}

class _OverlaySurface extends StatelessWidget {
  const _OverlaySurface({
    required this.state,
    required this.frameImage,
    required this.menuOpen,
    required this.menuAnchor,
    required this.onAction,
    required this.onSelectRegion,
    required this.onOpenMenu,
    required this.onCloseMenu,
    required this.onMenuAction,
  });

  final _OverlayState state;
  final MemoryImage? frameImage;
  final bool menuOpen;
  final OverlayPosition? menuAnchor;
  final Future<void> Function(String type) onAction;
  final Future<void> Function(Rect region) onSelectRegion;
  final Future<void> Function() onOpenMenu;
  final Future<void> Function() onCloseMenu;
  final Future<void> Function(String type) onMenuAction;

  @override
  Widget build(BuildContext context) {
    if (state.preparing) {
      return const Material(
        color: Colors.transparent,
        child: SizedBox.expand(),
      );
    }
    if (state.state == 'selecting') {
      return _RegionSelectionSurface(
        state: state,
        frameImage: frameImage,
        onAction: onAction,
        onSelectRegion: onSelectRegion,
      );
    }
    if (state.state == 'capturing' ||
        state.state == 'translating' ||
        state.state == 'result' ||
        state.state == 'error') {
      return _FullScreenSurface(
        state: state,
        frameImage: frameImage,
        onAction: onAction,
      );
    }
    if (menuOpen && menuAnchor == null) {
      return const Material(
        color: Colors.transparent,
        child: SizedBox.expand(),
      );
    }
    if (menuOpen && menuAnchor != null) {
      return _BubbleMenuSurface(
        state: state,
        anchor: menuAnchor!,
        onDismiss: onCloseMenu,
        onAction: onMenuAction,
      );
    }
    return _BubbleSurface(
      state: state,
      onAction: onAction,
      onOpenMenu: onOpenMenu,
    );
  }
}

class _RegionSelectionSurface extends StatefulWidget {
  const _RegionSelectionSurface({
    required this.state,
    required this.frameImage,
    required this.onAction,
    required this.onSelectRegion,
  });

  final _OverlayState state;
  final MemoryImage? frameImage;
  final Future<void> Function(String type) onAction;
  final Future<void> Function(Rect region) onSelectRegion;

  @override
  State<_RegionSelectionSurface> createState() =>
      _RegionSelectionSurfaceState();
}

class _RegionSelectionSurfaceState extends State<_RegionSelectionSurface> {
  Offset? _dragOrigin;
  Rect? _selection;
  bool _selectionValid = false;

  Rect _normalizedRect(Offset first, Offset second, Rect imageRect) {
    final startX = ((first.dx - imageRect.left) / imageRect.width).clamp(
      0.0,
      1.0,
    );
    final startY = ((first.dy - imageRect.top) / imageRect.height).clamp(
      0.0,
      1.0,
    );
    final endX = ((second.dx - imageRect.left) / imageRect.width).clamp(
      0.0,
      1.0,
    );
    final endY = ((second.dy - imageRect.top) / imageRect.height).clamp(
      0.0,
      1.0,
    );
    return Rect.fromLTRB(
      startX < endX ? startX : endX,
      startY < endY ? startY : endY,
      startX > endX ? startX : endX,
      startY > endY ? startY : endY,
    );
  }

  Rect _displayRect(Rect normalized, Rect imageRect) {
    return Rect.fromLTRB(
      imageRect.left + normalized.left * imageRect.width,
      imageRect.top + normalized.top * imageRect.height,
      imageRect.left + normalized.right * imageRect.width,
      imageRect.top + normalized.bottom * imageRect.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final imageRatio =
        widget.state.frameWidth > 0 && widget.state.frameHeight > 0
        ? widget.state.frameWidth / widget.state.frameHeight
        : 1.0;
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final imageRect = containedImageRect(
                    viewport: Size(constraints.maxWidth, constraints.maxHeight),
                    imageAspectRatio: imageRatio,
                  );
                  final displaySelection = _selection == null
                      ? null
                      : _displayRect(_selection!, imageRect);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.frameImage != null)
                        Image(
                          image: widget.frameImage!,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                      if (displaySelection != null)
                        Positioned.fromRect(
                          rect: displaySelection,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.lightBlueAccent.withValues(
                                  alpha: 0.2,
                                ),
                                border: Border.all(
                                  color: Colors.lightBlueAccent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: GestureDetector(
                          key: const ValueKey('region-selection-canvas'),
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) {
                            if (!imageRect.contains(details.localPosition)) {
                              setState(() {
                                _dragOrigin = null;
                                _selection = null;
                                _selectionValid = false;
                              });
                              return;
                            }
                            setState(() {
                              _dragOrigin = details.localPosition;
                              _selection = null;
                              _selectionValid = false;
                            });
                          },
                          onPanUpdate: (details) {
                            final origin = _dragOrigin;
                            if (origin == null) return;
                            final selection = _normalizedRect(
                              origin,
                              details.localPosition,
                              imageRect,
                            );
                            setState(() {
                              _selection = selection;
                              _selectionValid =
                                  selection.width * imageRect.width >= 8 &&
                                  selection.height * imageRect.height >= 8;
                            });
                          },
                          onPanEnd: (_) => setState(() => _dragOrigin = null),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.68),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text(
                                l10n.translationSelectRegionHint,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: SizedBox(
                height: 64,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => unawaited(widget.onAction('cancel')),
                      icon: const Icon(Icons.close),
                      label: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _selectionValid
                          ? () => unawaited(widget.onSelectRegion(_selection!))
                          : null,
                      icon: const Icon(Icons.translate),
                      label: Text(l10n.translationConfirmRegion),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleIcon extends StatelessWidget {
  const _BubbleIcon({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xff2f6f73),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: busy
          ? const Padding(
              padding: EdgeInsets.all(15),
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.translate, color: Colors.white),
    );
  }
}

class _BubbleSurface extends StatelessWidget {
  const _BubbleSurface({
    required this.state,
    required this.onAction,
    required this.onOpenMenu,
  });

  final _OverlayState state;
  final Future<void> Function(String type) onAction;
  final Future<void> Function() onOpenMenu;

  @override
  Widget build(BuildContext context) {
    if (state.preparing) {
      return const Material(
        color: Colors.transparent,
        child: SizedBox.expand(),
      );
    }
    final busy = state.state == 'starting';
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: state.state == 'ready' && !state.preparing
            ? () => unawaited(onAction('translate'))
            : null,
        onLongPress: () => unawaited(onOpenMenu()),
        child: Center(child: _BubbleIcon(busy: busy)),
      ),
    );
  }
}

class _BubbleMenuSurface extends StatelessWidget {
  const _BubbleMenuSurface({
    required this.state,
    required this.anchor,
    required this.onDismiss,
    required this.onAction,
  });

  final _OverlayState state;
  final OverlayPosition anchor;
  final Future<void> Function() onDismiss;
  final Future<void> Function(String type) onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final windowSize = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final bubble = OverlayPositioning.bubbleRect(anchor, windowSize);
    final busy = state.state == 'starting';
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(onDismiss()),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: bubble.left,
            top: bubble.top,
            width: bubble.width,
            height: bubble.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(onDismiss()),
              child: Center(child: _BubbleIcon(busy: busy)),
            ),
          ),
          CustomSingleChildLayout(
            delegate: _BubbleMenuLayoutDelegate(
              bubbleRect: bubble,
              safePadding: safePadding,
            ),
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surface,
              clipBehavior: Clip.antiAlias,
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BubbleMenuItem(
                      icon: Icons.fullscreen,
                      label: l10n.translationModeFullScreen,
                      selected: state.translationMode == 'fullScreen',
                      onTap: () => unawaited(onAction('modeFullScreen')),
                    ),
                    _BubbleMenuItem(
                      icon: Icons.crop_free,
                      label: l10n.translationModeRegion,
                      selected: state.translationMode == 'region',
                      onTap: () => unawaited(onAction('modeRegion')),
                    ),
                    if (state.translationMode == 'region' &&
                        state.hasSelectedRegion)
                      _BubbleMenuItem(
                        icon: Icons.crop,
                        label: l10n.translationModeRegionSelected,
                        onTap: () => unawaited(onAction('reselectRegion')),
                      ),
                    const Divider(height: 1),
                    _BubbleMenuItem(
                      icon: Icons.settings,
                      label: l10n.settings,
                      onTap: () => unawaited(onAction('openSettings')),
                    ),
                    const Divider(height: 1),
                    _BubbleMenuItem(
                      icon: Icons.close,
                      label: l10n.closeResult,
                      onTap: () => unawaited(onAction('stop')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleMenuItem extends StatelessWidget {
  const _BubbleMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(label),
            if (selected) ...[
              const SizedBox(width: 16),
              const Icon(Icons.check, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _BubbleMenuLayoutDelegate extends SingleChildLayoutDelegate {
  const _BubbleMenuLayoutDelegate({
    required this.bubbleRect,
    required this.safePadding,
  });

  final Rect bubbleRect;
  final EdgeInsets safePadding;

  static const double _gap = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = (constraints.maxWidth - safePadding.horizontal - 16).clamp(
      0.0,
      constraints.maxWidth,
    );
    final maxHeight = (constraints.maxHeight - safePadding.vertical - 16)
        .clamp(0.0, constraints.maxHeight);
    return BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final preferLeft = bubbleRect.center.dx >= size.width / 2;
    final minX = safePadding.left + _gap;
    var maxX = size.width - safePadding.right - _gap - childSize.width;
    if (maxX < minX) {
      maxX = minX;
    }
    final minY = safePadding.top + _gap;
    var maxY = size.height - safePadding.bottom - _gap - childSize.height;
    if (maxY < minY) {
      maxY = minY;
    }
    final x = preferLeft
        ? bubbleRect.left - _gap - childSize.width
        : bubbleRect.right + _gap;
    final y = bubbleRect.center.dy - childSize.height / 2;
    return Offset(x.clamp(minX, maxX), y.clamp(minY, maxY));
  }

  @override
  bool shouldRelayout(_BubbleMenuLayoutDelegate oldDelegate) {
    return bubbleRect != oldDelegate.bubbleRect ||
        safePadding != oldDelegate.safePadding;
  }
}

class _FullScreenSurface extends StatelessWidget {
  const _FullScreenSurface({
    required this.state,
    required this.frameImage,
    required this.onAction,
  });

  final _OverlayState state;
  final MemoryImage? frameImage;
  final Future<void> Function(String type) onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canCancel =
        state.state == 'capturing' || state.state == 'translating';
    final isError = state.state == 'error';
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (frameImage != null)
                    Image(
                      image: frameImage!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  if (state.result case final result?)
                    ImageTranslationOverlay(result: result),
                  if (isError)
                    Center(
                      child: Card(
                        margin: const EdgeInsets.all(24),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: SelectableText(
                            state.errorMessage ?? l10n.translationFailed(''),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  if (state.state == 'result' &&
                      state.result != null &&
                      state.result!.regions.isEmpty)
                    Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(l10n.imageTranslationNoText),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: SizedBox(
                height: 64,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (state.progressStage case final stage?)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 16),
                          child: Text(
                            _progressText(
                              l10n,
                              stage,
                              state.progressRegionCount,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    if (canCancel)
                      TextButton.icon(
                        onPressed: () => unawaited(onAction('cancel')),
                        icon: const Icon(Icons.close),
                        label: Text(l10n.cancel),
                      )
                    else
                      TextButton.icon(
                        onPressed: () => unawaited(onAction('dismiss')),
                        icon: const Icon(Icons.done),
                        label: Text(l10n.closeResult),
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _progressText(AppLocalizations l10n, String stage, int count) {
    return switch (stage) {
      'recognizing' => l10n.imageTranslationRecognizing,
      'translating' => l10n.imageTranslationTranslating(count),
      'llmTranslating' => l10n.imageTranslationLlmInProgress,
      _ => l10n.translationInProgress,
    };
  }
}

class _OverlayState {
  const _OverlayState({
    this.sessionId,
    this.requestId,
    this.state = 'stopped',
    this.locale = 'en',
    this.translationMode = 'fullScreen',
    this.hasSelectedRegion = false,
    this.errorCode,
    this.errorMessage,
    this.frameBytes,
    this.frameWidth = 0,
    this.frameHeight = 0,
    this.result,
    this.preparing = false,
    this.progressStage,
    this.progressRegionCount = 0,
  });

  final String? sessionId;
  final String? requestId;
  final String state;
  final String locale;
  final String translationMode;
  final bool hasSelectedRegion;
  final String? errorCode;
  final String? errorMessage;
  final Uint8List? frameBytes;
  final int frameWidth;
  final int frameHeight;
  final ImageTranslationResult? result;
  final bool preparing;
  final String? progressStage;
  final int progressRegionCount;

  _OverlayState copyWith({
    String? sessionId,
    String? requestId,
    String? state,
    String? locale,
    String? translationMode,
    bool? hasSelectedRegion,
    String? errorCode,
    String? errorMessage,
    Uint8List? frameBytes,
    int? frameWidth,
    int? frameHeight,
    ImageTranslationResult? result,
    bool? preparing,
    String? progressStage,
    int? progressRegionCount,
    bool clearRequest = false,
    bool clearFrame = false,
    bool clearResult = false,
    bool clearProgress = false,
    bool clearError = false,
  }) {
    return _OverlayState(
      sessionId: sessionId ?? this.sessionId,
      requestId: clearRequest ? null : requestId ?? this.requestId,
      state: state ?? this.state,
      locale: locale ?? this.locale,
      translationMode: translationMode ?? this.translationMode,
      hasSelectedRegion: hasSelectedRegion ?? this.hasSelectedRegion,
      errorCode: clearError ? errorCode : errorCode ?? this.errorCode,
      errorMessage: clearError
          ? errorMessage
          : errorMessage ?? this.errorMessage,
      frameBytes: clearFrame ? null : frameBytes ?? this.frameBytes,
      frameWidth: frameWidth ?? this.frameWidth,
      frameHeight: frameHeight ?? this.frameHeight,
      result: clearResult ? null : result ?? this.result,
      preparing: preparing ?? this.preparing,
      progressStage: clearProgress ? null : progressStage ?? this.progressStage,
      progressRegionCount: clearProgress
          ? 0
          : progressRegionCount ?? this.progressRegionCount,
    );
  }
}

int _asInt(Object? value) => value is int ? value : 0;
