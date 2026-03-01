import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Saves [bytes] to a file named [fileName] in the Downloads directory
/// (desktop) or application documents directory (mobile).
Future<void> saveFile(String fileName, List<int> bytes) async {
  Directory dir;
  // Try Downloads first (desktop), fallback to app documents
  try {
    dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  } catch (_) {
    dir = await getApplicationDocumentsDirectory();
  }
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
}
