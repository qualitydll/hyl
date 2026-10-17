import 'dart:io';

import 'package:path/path.dart' as p;

const mihomoConfigFileName = 'config.yaml';

String mihomoHomeDirectory(String dataDirectory) =>
    p.join(dataDirectory, 'home');

String mihomoConfigPath(String dataDirectory) =>
    p.join(mihomoHomeDirectory(dataDirectory), mihomoConfigFileName);

Future<File> prepareMihomoConfigFile(String dataDirectory) async {
  final file = File(mihomoConfigPath(dataDirectory));
  await file.parent.create(recursive: true);
  return file;
}
