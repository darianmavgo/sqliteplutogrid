import '../flight_service.dart';

/// Helper class for validating paths via Flight3 API
class PathValidator {
  /// Validates a path by calling Flight3's validation API
  /// Returns a map with validation results
  static Future<Map<String, dynamic>> validatePathBackwards(
    FlightService flight,
    String fullPath,
  ) async {
    try {
      return await flight.get(
        '/api/validate-path',
        queryParams: {'path': fullPath},
      );
    } catch (e) {
      print('[PathValidator] Error validating path: $e');
      return {
        'valid': false,
        'error_message': 'Failed to validate path: ${e.toString()}',
      };
    }
  }
  
  /// Generate a user-friendly error message via Flight3 API
  static Future<String> generateSmartErrorMessage(
    FlightService flight,
    String fullPath,
  ) async {
    final result = await validatePathBackwards(flight, fullPath);
    
    // Return the error message from the server
    if (result['error_message'] != null && result['error_message'].isNotEmpty) {
      return result['error_message'];
    }
    
    // Fallback formatting if server doesn't provide one
    final validSegments = result['valid_segments'] as List? ?? [];
    final breakPoint = result['break_point'] as String? ?? '';
    
    if (validSegments.isEmpty) {
      return 'Path not found: $fullPath\n\n'
          'The entire path does not exist.\n'
          'Tip: Check if you\'re in the right directory or if the file was moved.';
    }
    
    return 'Path not found:\n\n'
        '✓ Valid: ${validSegments.join("/")}\n'
        '✗ Not found: $breakPoint\n\n'
        'The path breaks at "$breakPoint".\n'
        'Double-click "${validSegments.join("/")}" in the breadcrumb bar to navigate to the last valid location.';
  }
}
