// Extracting archives: real progress, cancelling, and 7-Zip's output.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/providers/downloads_provider.dart' show downloadStopMessage;
import 'package:vn_pathfinder/services/extraction_service.dart';

/// Notes how far through its input a file was when the first byte came out.
class _FirstWrite extends OutputMemoryStream {
  final InputStream input;
  int? readBeforeFirstWrite;
  _FirstWrite(this.input);

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    readBeforeFirstWrite ??= input.position;
    super.writeBytes(bytes, length: length);
  }
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('vnp_extract'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// A ZIP of [count] files, each [size] bytes.
  String makeZip(int count, int size) {
    final archive = Archive();
    for (var i = 0; i < count; i++) {
      archive.addFile(ArchiveFile.bytes('game/data/file$i.bin', Uint8List(size)));
    }
    final path = p.join(temp.path, 'test.zip');
    File(path).writeAsBytesSync(ZipEncoder().encode(archive));
    return path;
  }

  test('a ZIP unpacks to disk and reports real bytes', () async {
    final zip = makeZip(3, 200000);
    final dest = Directory(p.join(temp.path, 'out'))..createSync();
    final updates = <ExtractionProgress>[];

    await ExtractionJob().extractZip(zip, dest.path, updates.add);

    for (var i = 0; i < 3; i++) {
      expect(File(p.join(dest.path, 'game', 'data', 'file$i.bin')).lengthSync(), 200000);
    }
    expect(updates.last.bytesDone, 600000);
    expect(updates.last.bytesTotal, 600000);
    expect(updates.last.filesDone, 3);
    expect(updates.last.filesTotal, 3);
    expect(updates.last.fraction, 1.0);
    expect(updates.last.currentFile, 'file2.bin');
  });

  test('cancelling stops the extraction', () async {
    final zip = makeZip(40, 2000000);
    final dest = Directory(p.join(temp.path, 'out'))..createSync();
    final job = ExtractionJob();
    var cancelled = false;

    await expectLater(
      job.extractZip(zip, dest.path, (update) {
        if (!cancelled) {
          cancelled = true;
          job.cancel();
        }
      }),
      throwsA(isA<ExtractionCancelled>()),
    );
    final written = dest.listSync(recursive: true).whereType<File>().length;
    expect(written, lessThan(40));
  });

  test('a broken archive reports an error', () async {
    final bad = File(p.join(temp.path, 'bad.zip'))..writeAsBytesSync([1, 2, 3, 4]);
    await expectLater(
      ExtractionJob().extractZip(bad.path, temp.path, (_) {}),
      throwsA(anything),
    );
  });

  group('large files inside a ZIP', () {
    /// Noise, so the compressed file is as big as the real one.
    Uint8List noise(int size) {
      final random = Random(1);
      return Uint8List.fromList(List.generate(size, (_) => random.nextInt(256)));
    }

    test('a compressed file is written as it unpacks, not gathered in memory first', () {
      final data = noise(8 * 1024 * 1024);
      final path = p.join(temp.path, 'big.zip');
      File(path).writeAsBytesSync(ZipEncoder().encode(Archive()..addFile(ArchiveFile.bytes('big.bin', data))));

      final input = InputFileStream(path);
      addTearDown(input.closeSync);
      final file = ZipDecoder().decodeStream(input).files.single;
      expect(file.compression, CompressionType.deflate);
      final raw = file.rawContent!.getStream(decompress: false);
      final size = raw.length;
      final out = _FirstWrite(raw);

      unpackZipFile(file, out);

      expect(out.getBytes(), data);
      expect(out.readBeforeFirstWrite, lessThan(size ~/ 4));
    });

    test('a file stored without compression unpacks too', () {
      final data = noise(100000);
      final path = p.join(temp.path, 'stored.zip');
      final entry = ArchiveFile.bytes('stored.bin', data)..compression = CompressionType.none;
      File(path).writeAsBytesSync(ZipEncoder().encode(Archive()..addFile(entry)));

      final input = InputFileStream(path);
      addTearDown(input.closeSync);
      final out = OutputMemoryStream();
      unpackZipFile(ZipDecoder().decodeStream(input).files.single, out);
      expect(out.getBytes(), data);
    });

    test('compressed files and their empty neighbours come out whole', () async {
      final data = noise(300000);
      final path = p.join(temp.path, 'mixed.zip');
      File(path).writeAsBytesSync(ZipEncoder().encode(Archive()
        ..addFile(ArchiveFile.bytes('game/one.bin', data))
        ..addFile(ArchiveFile.bytes('game/empty.txt', Uint8List(0)))
        ..addFile(ArchiveFile.bytes('game/zeros.bin', Uint8List(500000)))));
      final dest = Directory(p.join(temp.path, 'out'))..createSync();

      await ExtractionJob().extractZip(path, dest.path, (_) {});

      expect(File(p.join(dest.path, 'game', 'one.bin')).readAsBytesSync(), data);
      expect(File(p.join(dest.path, 'game', 'empty.txt')).lengthSync(), 0);
      expect(File(p.join(dest.path, 'game', 'zeros.bin')).lengthSync(), 500000);
    });

    test('a download that stopped partway says so', () async {
      final whole = File(makeZip(3, 200000)).readAsBytesSync();
      final partial = File(p.join(temp.path, 'partial.zip'))..writeAsBytesSync(whole.sublist(0, whole.length ~/ 2));
      await expectLater(
        ExtractionJob().extractZip(partial.path, temp.path, (_) {}),
        throwsA(contains('incomplete or damaged')),
      );
    });
  });

  group('why a download stopped', () {
    test('says what happened, and keeps the number', () {
      expect(downloadStopMessage(3), 'Download stopped: the disk is full (3)');
      expect(downloadStopMessage(14), 'Download stopped: your connection dropped (14)');
      expect(downloadStopMessage(24), 'Download stopped: the host cut it off (24)');
    });

    test('says how many tries it took', () {
      expect(downloadStopMessage(24, tries: 6), 'Download stopped: the host cut it off (24), after 6 tries');
      expect(downloadStopMessage(24), isNot(contains('tries')));
    });

    test('an unknown reason still gives the number', () {
      expect(downloadStopMessage(99), 'Download stopped (99)');
      expect(downloadStopMessage(0), 'Download stopped (0)');
    });
  });

  group('speed and time left', () {
    const halfway = ExtractionProgress(bytesDone: 500, bytesTotal: 1000);

    test('come from the bytes done so far', () {
      expect(halfway.speed(const Duration(seconds: 5)), 100);
      expect(halfway.timeLeft(const Duration(seconds: 5)), const Duration(seconds: 5));
    });

    test('are unknown just after starting', () {
      expect(halfway.speed(const Duration(milliseconds: 100)), 0);
      expect(halfway.timeLeft(const Duration(milliseconds: 100)), isNull);
    });
  });

  group('parseSevenZipProgress', () {
    test('reads percent, file count and name', () {
      final r = parseSevenZipProgress(' 42% 12 - game/images/archive.rpa');
      expect(r?.percent, 42);
      expect(r?.files, 12);
      expect(r?.file, 'archive.rpa');
    });

    test('takes the latest line in a chunk', () {
      final r = parseSevenZipProgress(' 10% 1 - a.bin\x08\x08\x08 25% 2 - b.bin\r');
      expect(r?.percent, 25);
      expect(r?.file, 'b.bin');
    });

    test('reads a bare percentage', () => expect(parseSevenZipProgress('  7%')?.percent, 7));

    test('ignores other output', () => expect(parseSevenZipProgress('7-Zip 24.08'), isNull));
  });
}
