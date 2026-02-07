# GoDart Plan: Integrating Banquet with SQLiter-Dart

This plan outlines the steps to integrate the **Banquet** URL parsing library (written in Go) into the **SQLiter-Dart** application (written in Dart/Flutter) using **Frign Function Interface (FFI)**. This integration will enable SQLiter-Dart to understand and process Banquet-compliant URLs, ensuring consistency with the **Flight3** ecosystem.

## Objective

To empower SQLiter-Dart with the ability to parse complex data URLs (e.g., `path/to/db.sqlite;Table;Column[0:10]`) by leveraging the existing, canonical Go implementation of Banquet. This avoids logic duplication and ensures that the desktop application behaves identically to the server-side components of Flight3.

## Architecture

The integration relies on compiling the Go code into a **C-shared library** (`libbanquet`) and loading it within the Dart application using `dart:ffi`.

### Data Flow
1.  **Input**: User enters a string (URL or Path) in SQLiter-Dart.
2.  **Bridge**: Dart passes this string to the Go `ParseBanquet` function via FFI.
3.  **Processing**: Go parses the string using the `banquet` library, handling all heuristics, slice notation, and query parameters.
4.  **Output**: Go returns a JSON representation of the `Banquet` struct (Dataset, Table, Columns, etc.).
5.  **Action**: SQLiter-Dart deserializes the JSON and configures the UI (opens DB, selects table, applies filters).

## Implementation Plan

### Phase 1: Go Bridge (`libbanquet`)

We need to create a bridge package in the `banquet` repository that exports C-compatible functions.

**1. Create Bridge Source (`banquet/bridge/bridge.go`)**
```go
package main

import "C"
import (
	"encoding/json"
	"github.com/darianmavgo/banquet"
)

//export ParseBanquetJSON
func ParseBanquetJSON(rawUrl *C.char) *C.char {
	goStr := C.GoString(rawUrl)
	b, err := banquet.ParseBanquet(goStr)
	if err != nil {
		// Return empty JSON or error structure
		return C.CString("{\"error\": \"" + err.Error() + "\"}")
	}
	
	// Marshaling just the fields we need (or the whole struct if tagged properly)
	// We might need a wrapper struct if Banquet doesn't have JSON tags or has incompatible types for simple marshaling
	jsonData, _ := json.Marshal(b)
	return C.CString(string(jsonData))
}

//export FreeString
func FreeString(str *C.char) {
	C.free(unsafe.Pointer(str))
}

func main() {}
```

**2. Build Script (`banquet/build_lib.sh`)**
```bash
go build -o libbanquet.dylib -buildmode=c-shared ./bridge
# For other platforms:
# go build -o libbanquet.so -buildmode=c-shared ./bridge (Linux)
# go build -o libbanquet.dll -buildmode=c-shared ./bridge (Windows)
```

### Phase 2: Dart FFI Layer

**1. Add Dependencies**
Add `ffi` to `pubspec.yaml`.

**2. Create Bindings (`lib/banquet_bridge.dart`)**
```dart
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'dart:io';
import 'dart:convert';

typedef ParseBanquetJsonC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> str);
typedef ParseBanquetJsonDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> str);

typedef FreeStringC = ffi.Void Function(ffi.Pointer<Utf8> str);
typedef FreeStringDart = void Function(ffi.Pointer<Utf8> str);

class BanquetBridge {
  late ffi.DynamicLibrary _lib;
  late ParseBanquetJsonDart _parseBanquetJson;
  late FreeStringDart _freeString;

  BanquetBridge() {
    // Platform-specific loading
    if (Platform.isMacOS) {
      _lib = ffi.DynamicLibrary.open('libbanquet.dylib');
    } else if (Platform.isWindows) {
      _lib = ffi.DynamicLibrary.open('libbanquet.dll');
    } else {
      _lib = ffi.DynamicLibrary.open('libbanquet.so');
    }

    _parseBanquetJson = _lib
        .lookup<ffi.NativeFunction<ParseBanquetJsonC>>('ParseBanquetJSON')
        .asFunction();
        
    _freeString = _lib
        .lookup<ffi.NativeFunction<FreeStringC>>('FreeString')
        .asFunction();
  }

  Map<String, dynamic>? parse(String url) {
    final cStr = url.toNativeUtf8();
    final resultPtr = _parseBanquetJson(cStr);
    final jsonStr = resultPtr.toDartString();
    
    malloc.free(cStr);
    _freeString(resultPtr); // Important: Free memory allocated by Go

    try {
      return jsonDecode(jsonStr);
    } catch (e) {
      print("Error decoding Banquet JSON: $e");
      return null;
    }
  }
}
```

### Phase 3: SQLiter-Dart Integration

**1. Update `DBViewerPage` (`lib/main.dart`)**
Modify the `_loadPath` function to use the bridge.

```dart
Future<void> _loadPath() async {
  final input = _pathController.text.trim();
  
  // Try parsing as Banquet URL first
  final banquetData = _banquetBridge.parse(input);
  
  if (banquetData != null && !banquetData.containsKey('error')) {
     final dbPath = banquetData['DataSetPath'];
     final table = banquetData['Table'];
     // ... use other fields like Select, Where, Limit
     
     // Proceed to load DB at dbPath
     // If table is present, auto-select it
  } else {
     // Fallback to standard raw path handling
  }
}
```

**2. Deployment**
Ensure `libbanquet.dylib` is placed in the correct directory where the Dart executable (or Flutter runner) can find it. For development, it can be in the root or a known lib folder.

## Integration with Flight3

By implementing this, **SQLiter-Dart** becomes a "Banquet-Native" application. 
- **Usefulness to Flight3**: Flight3 (the server) works inherently with Banquet URLs. Users can copy a URL from a Flight3 web interface and paste it directly into SQLiter-Dart to view the same data context (same table, same filters) in a native desktop experience.
- **Future**: Validated URLs constructed from the desktop app can be shared back to the Flight3 server or other users.

## Next Steps

1.  Author the Go bridge code in `banquet`.
2.  Compile the library.
3.  Implement the Dart bindings.
4.  Wire it up in the Flutter UI.
