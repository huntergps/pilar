import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Saves [bytes] as a file download in the browser.
Future<void> saveFile(String fileName, List<int> bytes) async {
  final uint8 = Uint8List.fromList(bytes);
  final blob = web.Blob(
    [uint8.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = fileName;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
