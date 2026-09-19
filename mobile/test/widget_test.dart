import 'package:flutter_test/flutter_test.dart';
import 'package:groopx/main.dart';

void main() {
  testWidgets('GroopX renders its welcome screen', (tester) async {
    await tester.pumpWidget(const GroopXApp());
    await tester.pumpAndSettle();
    expect(find.text('GroopX'), findsOneWidget);
  });
}
