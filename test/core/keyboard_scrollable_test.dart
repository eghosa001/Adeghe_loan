import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:loantrack/core/utils/platform_utils.dart';
import 'package:loantrack/core/widgets/keyboard_scrollable.dart';

void main() {
  testWidgets(
      'mounting KeyboardScrollable does NOT steal focus from a focused text '
      'field (regression: keyboard goes away mid-typing)', (tester) async {
    if (!isDesktopPlatform) return;
    final textFieldFocus = FocusNode();
    addTearDown(textFieldFocus.dispose);

    Widget build({Key? scrollKey}) => MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: textFieldFocus),
                const SizedBox(height: 40),
                KeyboardScrollable(
                  key: scrollKey,
                  child: Container(height: 200, color: Colors.grey),
                ),
              ],
            ),
          ),
        );

    await tester.pumpWidget(build());
    await tester.pump();

    textFieldFocus.requestFocus();
    await tester.pump();
    expect(textFieldFocus.hasFocus, isTrue);

    // Remount KeyboardScrollable — simulates an async reload swapping the
    // subtree (results crossing the empty boundary) while the user is typing.
    await tester.pumpWidget(build(scrollKey: const ValueKey('reload')));
    await tester.pump();
    await tester.pump();

    expect(textFieldFocus.hasFocus, isTrue,
        reason: 'KeyboardScrollable must not steal focus from a text field');
  });

  testWidgets('KeyboardScrollable takes focus when nothing editable is focused',
      (tester) async {
    if (!isDesktopPlatform) return;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: KeyboardScrollable(child: SizedBox(height: 200))),
      ),
    );
    await tester.pump();
    await tester.pump();

    final primary = FocusManager.instance.primaryFocus;
    expect(primary, isNotNull);
    final ctx = primary!.context;
    expect(ctx, isNotNull);
    final insideScrollable =
        ctx!.widget is KeyboardScrollable ||
            ctx.findAncestorWidgetOfExactType<KeyboardScrollable>() != null;
    expect(insideScrollable, isTrue,
        reason: 'arrow-key scrolling needs the scroll area focused');
  });
}
