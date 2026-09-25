import 'dart:io';

String saveCsv(List<int> bytes, String filename) {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  final downloads = Directory('$home${Platform.pathSeparator}Downloads');
  final destination = downloads.existsSync()
      ? File('${downloads.path}${Platform.pathSeparator}$filename')
      : File('${Directory.current.path}${Platform.pathSeparator}$filename');
  destination.writeAsBytesSync(bytes);
  return destination.path;
}
