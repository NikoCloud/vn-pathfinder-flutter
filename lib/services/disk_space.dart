import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Free and total space on the drive that holds a folder.
class DiskSpace {
  final int free;
  final int total;
  const DiskSpace(this.free, this.total);

  double get usedFraction => total <= 0 ? 0 : (1 - free / total).clamp(0.0, 1.0);
}

typedef _GetDiskFreeSpaceExNative = Int32 Function(
    Pointer<Utf16> dir, Pointer<Uint64> freeToCaller, Pointer<Uint64> total, Pointer<Uint64> totalFree);
typedef _GetDiskFreeSpaceExDart = int Function(
    Pointer<Utf16> dir, Pointer<Uint64> freeToCaller, Pointer<Uint64> total, Pointer<Uint64> totalFree);

/// Asks Windows how much room is left for [folder]. Works for network shares
/// too. Null when the folder isn't reachable or this isn't Windows. Runs on a
/// background isolate, since a share that has gone away can take a while to
/// answer.
Future<DiskSpace?> diskSpaceFor(String folder) async {
  if (!Platform.isWindows || folder.isEmpty) return null;
  return Isolate.run(() => _query(folder));
}

DiskSpace? _query(String folder) {
  if (!Directory(folder).existsSync()) return null;
  final fn = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<_GetDiskFreeSpaceExNative, _GetDiskFreeSpaceExDart>('GetDiskFreeSpaceExW');
  final path = folder.toNativeUtf16();
  final free = calloc<Uint64>(), total = calloc<Uint64>(), totalFree = calloc<Uint64>();
  try {
    if (fn(path, free, total, totalFree) == 0) return null;
    return DiskSpace(free.value, total.value);
  } finally {
    calloc.free(path);
    calloc.free(free);
    calloc.free(total);
    calloc.free(totalFree);
  }
}

/// "412 GB", "1.8 TB", "640 MB".
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final digits = v >= 100 || i == 0 ? 0 : 1;
  return '${v.toStringAsFixed(digits)} ${units[i]}';
}
