// Storage backend selection.
//
// The web build talks to IndexedDB; every other target (including `flutter
// test`) gets an in-memory database so the same code paths stay testable.
export 'db_factory_io.dart' if (dart.library.js_interop) 'db_factory_web.dart';