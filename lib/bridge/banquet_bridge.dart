import 'dart:ffi';
import 'dart:io';
import 'dart:convert';
import 'package:ffi/ffi.dart';

// FFI signatures
typedef BanquetParseC = Pointer<Utf8> Function(Pointer<Utf8> url);
typedef BanquetParseDart = Pointer<Utf8> Function(Pointer<Utf8> url);

typedef FreeStringC = Void Function(Pointer<Utf8> str);
typedef FreeStringDart = void Function(Pointer<Utf8> str);

class BanquetBridge {
  static DynamicLibrary? _lib;

  static void initialize() {
    if (_lib != null) return;

    if (Platform.isMacOS) {
      const libName = 'libbanquet.dylib';
      try {
        _lib = DynamicLibrary.open(libName);
      } catch (e) {
        print('Failed to load $libName from default path: $e');
        // For development, sometimes full path is needed if not bundled
        // We throw here to let the caller handle or debug
        rethrow;
      }
    } else {
        throw UnsupportedError('Unsupported platform');
    }
  }

  static Map<String, dynamic> parse(String url) {
    initialize();
    if (_lib == null) throw Exception('Banquet library not initialized');

    final parseFunc = _lib!.lookupFunction<BanquetParseC, BanquetParseDart>('BanquetParse');
    final freeFunc = _lib!.lookupFunction<FreeStringC, FreeStringDart>('FreeString');

    final urlPtr = url.toNativeUtf8();
    try {
      final resultPtr = parseFunc(urlPtr);
      final jsonString = resultPtr.toDartString();
      freeFunc(resultPtr);

      final decoded = jsonDecode(jsonString);
      if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
         throw Exception(decoded['error']); // It's an error from Go
      }
      return decoded as Map<String, dynamic>;
    } finally {
      calloc.free(urlPtr);
    }
  }
}
