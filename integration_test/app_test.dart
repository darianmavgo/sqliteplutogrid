import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqliter/main.dart' as app;
import 'package:sqliter/widgets/database_grid_view.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('End-to-end verified app launch', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();
    
    // Verify Home State
    expect(find.text('🍊'), findsOneWidget);

    // Verify grid structure first
    await tester.pumpAndSettle(const Duration(seconds: 3));
    
    // Check for error view
    final errorFinder = find.textContaining('Error');
    if (errorFinder.evaluate().isNotEmpty) {
       debugPrint("Found Error View! Dumping details...");
       final allText = find.byType(Text);
       debugPrint("All visible text:");
       for (var element in allText.evaluate()) {
          debugPrint((element.widget as Text).data);
       }
       fail("App showed Error View");
    }

    // Check for Grid
    expect(find.byType(DatabaseGridView), findsOneWidget, reason: "Grid not found");

    // "Open Local File" is a label
    await tester.pumpAndSettle(const Duration(seconds: 5)); 
    expect(find.textContaining('Open Local File'), findsOneWidget, reason: "Quick link text not found");
  });
}
