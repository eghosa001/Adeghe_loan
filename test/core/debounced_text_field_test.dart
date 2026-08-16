import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:loantrack/core/widgets/debounced_text_field.dart';

void main() {
  testWidgets(
      're-seeds its controller from initialValue when remounted (typed search '
      'survives a hard reload)', (tester) async {
    final changed = <String>[];
    Widget build(String initialValue) => MaterialApp(
          home: Scaffold(
            body: DebouncedTextField(
              initialValue: initialValue,
              onChanged: changed.add,
            ),
          ),
        );

    await tester.pumpWidget(build(''));
    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.pump(const Duration(milliseconds: 350));
    expect(changed.last, 'Ada');

    // Simulate a hard reload: the widget unmounts and remounts seeded with the
    // query provider's latest value.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(build('Ada'));

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Ada',
    );
  });
}
