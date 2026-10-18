/// Chooses the right database opener for the platform at compile time.
///
/// `dart.library.io` is true on Android, iOS, Windows, macOS and Linux;
/// `dart.library.js_interop` is true on the web. Exactly one of the three
/// implementations below is ever compiled into a given build.
library;

export 'stub.dart'
    if (dart.library.io) 'native.dart'
    if (dart.library.js_interop) 'web.dart';
