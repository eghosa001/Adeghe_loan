import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/widgets/app_numpad.dart';

/// Locks in the screen-reader contract of the shared PIN keypad:
/// every digit key is exposed to the semantics tree as a tappable button
/// labeled with its digit, and the delete key is labeled 'Delete' and
/// actionable — a TalkBack/VoiceOver user must be able to enter and correct a
/// PIN entirely by touch/keyboard navigation.
void main() {
  late List<String> pressed;
  late int deletes;

  setUp(() {
    pressed = [];
    deletes = 0;
  });

  Widget buildNumpad() {
    return MaterialApp(
      home: Scaffold(
        body: AppNumpad(
          onKeyPressed: pressed.add,
          onDelete: () => deletes++,
        ),
      ),
    );
  }

  testWidgets('every digit key is a labeled, tappable semantic button',
      (tester) async {
    await tester.pumpWidget(buildNumpad());

    for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']) {
      final key = find.bySemanticsLabel(digit);
      expect(key, findsOneWidget, reason: '$digit key must be announced');
      // Confirm it is exposed as a button (not a plain text node).
      final semantics = tester.getSemantics(key);
      expect(
        semantics.flagsCollection.isButton,
        isTrue,
        reason: '$digit key must be a button for screen-reader activation',
      );
    }
  });

  testWidgets('tapping a digit key invokes onKeyPressed with that digit',
      (tester) async {
    await tester.pumpWidget(buildNumpad());

    await tester.tap(find.bySemanticsLabel('4'));
    await tester.tap(find.bySemanticsLabel('8'));
    expect(pressed, ['4', '8']);
  });

  testWidgets('the delete key is a labeled, tappable button', (tester) async {
    await tester.pumpWidget(buildNumpad());

    final delete = find.bySemanticsLabel('Delete');
    expect(delete, findsOneWidget);
    final semantics = tester.getSemantics(delete);
    expect(semantics.flagsCollection.isButton, isTrue);

    await tester.tap(delete);
    await tester.tap(delete);
    expect(deletes, 2);
  });

  testWidgets('all ten digit keys plus the delete key are present together',
      (tester) async {
    await tester.pumpWidget(buildNumpad());

    for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']) {
      expect(find.bySemanticsLabel(digit), findsOneWidget);
    }
    expect(find.bySemanticsLabel('Delete'), findsOneWidget);
  });
}


