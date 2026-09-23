/// Thin helpers over browser APIs used by journal.md: downloads, blob URLs,
/// prefers-reduced-motion and save-on-hide.
///
/// Conditional export: real implementations on the web, quiet stubs anywhere
/// else (unit tests, analysis) so `package:web` never leaks into the VM.
library;

export 'web_ext_stub.dart' if (dart.library.html) 'web_ext_web.dart';
