import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxlingo/l10n/app_localizations.dart';
import 'package:foxlingo/widgets/translation_progress_dialog.dart';

void main() {
  testWidgets('shows progress and closes automatically on success', (
    tester,
  ) async {
    final operation = Completer<String>();
    String? result;
    var completed = false;

    await tester.pumpWidget(
      _TestApp(
        onPressed: (context) async {
          result = await showTranslationProgressDialog<String>(
            context: context,
            operation: (_) => operation.future,
          );
          completed = true;
        },
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(find.text('Translating...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    operation.complete('translated');
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(completed, isTrue);
    expect(result, 'translated');
  });

  testWidgets('keeps the dialog open and displays translation errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        onPressed: (context) async {
          await showTranslationProgressDialog<void>(
            context: context,
            operation: (_) => Future<void>.error(StateError('boom')),
          );
        },
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Translation failed: Bad state: boom'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('displays validation errors without adding a failure prefix', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        onPressed: (context) async {
          await showTranslationProgressDialog<void>(
            context: context,
            operation: (_) => Future<void>.error(
              const TranslationDialogException('Configure translation first'),
            ),
          );
        },
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(find.text('Configure translation first'), findsOneWidget);
    expect(find.textContaining('Translation failed'), findsNothing);
  });

  testWidgets('cancel aborts the operation and ignores a late result', (
    tester,
  ) async {
    final operation = Completer<String>();
    Future<void>? abortTrigger;
    String? result;
    var completed = false;

    await tester.pumpWidget(
      _TestApp(
        onPressed: (context) async {
          result = await showTranslationProgressDialog<String>(
            context: context,
            operation: (trigger) {
              abortTrigger = trigger;
              return operation.future;
            },
          );
          completed = true;
        },
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(abortTrigger, isNotNull);

    var aborted = false;
    abortTrigger!.then((_) => aborted = true);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(aborted, isTrue);
    expect(completed, isTrue);
    expect(result, isNull);

    operation.complete('late translation');
    await tester.pump();
    expect(result, isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.onPressed});

  final Future<void> Function(BuildContext context) onPressed;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => onPressed(context),
            child: const Text('Start'),
          ),
        ),
      ),
    );
  }
}
