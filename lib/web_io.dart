// Browser file and download plumbing.
//
// The web build gets the real implementation; every other target gets a stub
// so `flutter test` compiles the whole app without a DOM.
export 'web_io_stub.dart' if (dart.library.js_interop) 'web_io_web.dart';