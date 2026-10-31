import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// How far an extraction has got. For RAR, 7-Zip only reports a percentage, so
/// the byte counts are that share of the archive's size.
class ExtractionProgress {
  final int bytesDone;
  final int bytesTotal;
  final int filesDone;
  final int filesTotal;
  final String currentFile;

  const ExtractionProgress({
    required this.bytesDone,
    required this.bytesTotal,
    this.filesDone = 0,
    this.filesTotal = 0,
    this.currentFile = '',
  });

  double get fraction => bytesTotal <= 0 ? 0 : (bytesDone / bytesTotal).clamp(0.0, 1.0);

  /// Bytes per second, given how long the extraction has been running.
  double speed(Duration elapsed) =>
      elapsed.inMilliseconds < 250 ? 0 : bytesDone * 1000 / elapsed.inMilliseconds;

  /// Time left at the current speed. Null until there's a speed to go on.
  Duration? timeLeft(Duration elapsed) {
    final s = speed(elapsed);
    if (s <= 0) return null;
    return Duration(seconds: ((bytesTotal - bytesDone).clamp(0, bytesTotal) / s).ceil());
  }
}

/// Thrown from an extraction stopped with [ExtractionJob.cancel].
class ExtractionCancelled implements Exception {
  const ExtractionCancelled();
}

/// One extraction, which can be cancelled while it runs. The caller owns the
/// destination folder and removes it after a failure or cancel.
class ExtractionJob {
  bool _cancelled = false;
  Process? _process;

  /// A file the ZIP worker watches for. A worker can't get messages while it's
  /// writing, and killing it would leave its files locked on Windows, so the
  /// folder couldn't be cleaned up.
  String? _cancelMarker;

  void cancel() {
    _cancelled = true;
    _process?.kill();
    final marker = _cancelMarker;
    if (marker != null) File(marker).createSync(recursive: true);
  }

  static const _workerExited = 'worker exited';

  /// Unpacks a ZIP on a background isolate, reading it from disk and writing
  /// each file as it goes, so neither a multi-gigabyte archive nor a
  /// multi-gigabyte file inside it has to fit in memory.
  Future<void> extractZip(
    String archive,
    String destDir,
    void Function(ExtractionProgress) onProgress,
  ) async {
    final port = ReceivePort();
    final finished = Completer<void>();
    void finish([Object? error]) {
      if (finished.isCompleted) return;
      error == null ? finished.complete() : finished.completeError(error);
    }

    port.listen((message) {
      if (message is ExtractionProgress) {
        onProgress(message);
      } else if (message == null) {
        finish();
      } else if (message == _workerExited) {
        finish('The extraction stopped unexpectedly.');
      } else if (message == _workerCancelled) {
        finish(const ExtractionCancelled());
      } else {
        finish(message.toString());
      }
    });
    try {
      final marker = _cancelMarker = p.join(destDir, '.cancel');
      final worker = await Isolate.spawn(
        _zipWorker,
        (archive, destDir, marker, port.sendPort),
        onError: port.sendPort,
      );
      worker.addOnExitListener(port.sendPort, response: _workerExited);
      if (_cancelled) cancel();
      await finished.future;
    } finally {
      port.close();
    }
  }

  /// Unpacks an archive with 7-Zip, following its progress output.
  Future<void> extractWith7Zip(
    String sevenZip,
    String archive,
    String destDir,
    void Function(ExtractionProgress) onProgress,
  ) async {
    final size = File(archive).lengthSync();
    final process = await Process.start(sevenZip, ['x', archive, '-o$destDir', '-y', '-bsp1', '-bb0']);
    _process = process;
    if (_cancelled) process.kill();

    final errors = StringBuffer();
    final stderr = process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(errors.write);
    final stdout = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((chunk) {
      final update = parseSevenZipProgress(chunk);
      if (update == null) return;
      onProgress(ExtractionProgress(
        bytesDone: size * update.percent ~/ 100,
        bytesTotal: size,
        filesDone: update.files,
        currentFile: update.file,
      ));
    });

    final code = await process.exitCode;
    await stdout.cancel();
    await stderr.cancel();
    if (_cancelled) throw const ExtractionCancelled();
    if (code != 0) throw '7-Zip extraction failed:\n$errors';
  }
}

/// The latest progress line in a chunk of 7-Zip output, like " 42% 12 - a.rpa".
({int percent, int files, String file})? parseSevenZipProgress(String chunk) {
  final matches = RegExp(r'(\d{1,3})%(?:\s+(\d+)\s*-\s*([^\r\n\x08]*))?').allMatches(chunk);
  if (matches.isEmpty) return null;
  final last = matches.last;
  return (
    percent: int.parse(last.group(1)!).clamp(0, 100),
    files: int.tryParse(last.group(2) ?? '') ?? 0,
    file: p.basename((last.group(3) ?? '').trim()),
  );
}

const _workerCancelled = 'worker cancelled';
const _unreadable = "This archive is incomplete or damaged, so it can't be unpacked.";

/// How much compressed data is unpacked at a time.
const _unpackChunk = 1024 * 1024;

/// Writes one file from a ZIP to [out] as it unpacks. The archive package's own
/// writeContent gathers a compressed file in memory until the end of it, and a
/// game's data files can be many gigabytes.
@visibleForTesting
void unpackZipFile(ArchiveFile file, OutputStream out) {
  final content = file.rawContent;
  if (content == null || file.compression != CompressionType.deflate) {
    file.writeContent(out);
    return;
  }
  final input = content.getStream(decompress: false);
  final inflate = RawZLibFilter.inflateFilter(raw: true);
  void drain({bool end = false}) {
    while (true) {
      final bytes = inflate.processed(flush: false, end: end);
      if (bytes == null) return;
      out.writeBytes(bytes);
    }
  }

  while (!input.isEOS) {
    final chunk = input.readBytes(min(_unpackChunk, input.length)).toUint8List();
    inflate.process(chunk, 0, chunk.length);
    drain();
  }
  drain(end: true);
}

class _StopWorker implements Exception {
  const _StopWorker();
}

void _zipWorker((String, String, String, SendPort) args) {
  final (archivePath, destDir, cancelMarker, port) = args;
  final input = InputFileStream(archivePath);
  try {
    final files = ZipDecoder().decodeStream(input).files.where((f) => f.isFile).toList();
    if (files.isEmpty) throw _unreadable;
    final total = files.fold<int>(0, (sum, f) => sum + f.size);
    final clock = Stopwatch()..start();
    var written = 0;
    var filesDone = 0;

    void report(String name, {bool force = false}) {
      if (!force && clock.elapsedMilliseconds < 120) return;
      clock.reset();
      if (File(cancelMarker).existsSync()) throw const _StopWorker();
      port.send(ExtractionProgress(
        bytesDone: written,
        bytesTotal: total,
        filesDone: filesDone,
        filesTotal: files.length,
        currentFile: p.basename(name),
      ));
    }

    for (final file in files) {
      final out = p.normalize(p.join(destDir, file.name));
      // Skip entries that would land outside the extraction folder ("../…").
      if (p.isWithin(destDir, out)) {
        Directory(p.dirname(out)).createSync(recursive: true);
        final sink = _CountingOutput(out, (n) {
          written += n;
          report(file.name);
        });
        try {
          unpackZipFile(file, sink);
        } finally {
          sink.closeSync();
          file.closeSync();
        }
      }
      filesDone++;
      report(file.name, force: true);
    }
    port.send(null);
  } on _StopWorker {
    port.send(_workerCancelled);
  } on ArchiveException {
    port.send(_unreadable);
  } on OutOfMemoryError {
    port.send('Not enough memory to unpack this archive.');
  } catch (e) {
    port.send('$e');
  } finally {
    input.closeSync();
  }
}

/// Reports bytes as they're written, so one huge file still shows progress.
class _CountingOutput extends OutputFileStream {
  final void Function(int) onWritten;
  _CountingOutput(String path, this.onWritten)
      : super.withFileHandle(FileHandle(path, mode: FileAccess.write));

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    super.writeBytes(bytes, length: length);
    onWritten(length ?? bytes.length);
  }
}
