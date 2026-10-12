import 'dart:typed_data';

// Browser APIs cannot validate public DNS destinations. Fail closed.
Future<Uint8List?> picture(String url) async => null;
void clearPictures() {}
