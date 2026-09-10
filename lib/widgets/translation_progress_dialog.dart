import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

typedef TranslationDialogOperation<T> =
    Future<T> Function(Future<void> abortTrigger);

class TranslationDialogException implements Exception {
  const TranslationDialogException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<T?> showTranslationProgressDialog<T>({
  required BuildContext context,
  required TranslationDialogOperation<T> operation,
  String? progressMessage,
  String? progressDetails,
  ValueListenable<String>? progressStatus,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _TranslationProgressDialog<T>(
      operation: operation,
      progressMessage: progressMessage,
      progressDetails: progressDetails,
      progressStatus: progressStatus,
    ),
  );
}

class _TranslationProgressDialog<T> extends StatefulWidget {
  const _TranslationProgressDialog({
    required this.operation,
    this.progressMessage,
    this.progressDetails,
    this.progressStatus,
  });

  final TranslationDialogOperation<T> operation;
  final String? progressMessage;
  final String? progressDetails;
  final ValueListenable<String>? progressStatus;

  @override
  State<_TranslationProgressDialog<T>> createState() =>
      _TranslationProgressDialogState<T>();
}

class _TranslationProgressDialogState<T>
    extends State<_TranslationProgressDialog<T>> {
  final Completer<void> _abortCompleter = Completer<void>();
  String? _errorMessage;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_runOperation());
      }
    });
  }

  Future<void> _runOperation() async {
    try {
      final result = await widget.operation(_abortCompleter.future);
      if (!mounted || _finished) {
        return;
      }

      _finished = true;
      Navigator.of(context).pop(result);
    } on Object catch (error) {
      if (!mounted || _finished) {
        return;
      }

      final l10n = AppLocalizations.of(context);
      final message = switch (error) {
        TranslationDialogException(:final message) => message,
        StateError()
            when error.toString().contains('No content to translate') =>
          l10n.translationNoContent,
        _ => l10n.translationFailed(error.toString()),
      };
      setState(() => _errorMessage = message);
    }
  }

  void _cancel() {
    if (_finished) {
      return;
    }

    _finished = true;
    if (!_abortCompleter.isCompleted) {
      _abortCompleter.complete();
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    if (!_finished && !_abortCompleter.isCompleted) {
      _abortCompleter.complete();
    }
    _finished = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final errorMessage = _errorMessage;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: errorMessage == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 16),
                    _progressMessageText(l10n, textAlign: TextAlign.center),
                    if (widget.progressDetails case final details?) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          details,
                          textAlign: TextAlign.start,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: SingleChildScrollView(
                    child: SelectableText(errorMessage),
                  ),
                ),
        ),
        actions: [TextButton(onPressed: _cancel, child: Text(l10n.cancel))],
      ),
    );
  }

  Widget _progressMessageText(
    AppLocalizations l10n, {
    TextAlign? textAlign,
  }) {
    final fallback = widget.progressMessage ?? l10n.translationInProgress;
    final progressStatus = widget.progressStatus;
    if (progressStatus == null) {
      return Text(fallback, textAlign: textAlign);
    }

    return ValueListenableBuilder<String>(
      valueListenable: progressStatus,
      builder: (context, status, _) => Text(
        status.isEmpty ? fallback : status,
        textAlign: textAlign,
      ),
    );
  }
}
