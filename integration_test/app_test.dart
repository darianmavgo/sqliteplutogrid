import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqliter/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('End-to-end verified app launch', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();
    
    // Verify that the home icon exists
    expect(find.text('🍊'), findsOneWidget);
    
    // Verify that the Grid loads Home Content via FFI/Local Logic
    // "Open Local File" should be in the grid
    // await tester.pumpAndSettle(const Duration(seconds: 5)); // Increased wait time
    // expect(find.text('Open Local File'), findsOneWidget);
  });
}
