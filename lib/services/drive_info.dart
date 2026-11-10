import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Where a folder lives, for deciding whether Trash is safe (#21). Trash is
/// offered only for an internal, local drive whose file system keeps a
/// recycle bin. Removable drives keep trashed files hidden on the drive
/// itself (a ghost file that only a format removes), on every OS; network
/// shares have no Trash at all. Anything uncertain counts as not safe.
enum DriveKind { internal, removable, network, unknown }

class DriveInfo {
  final DriveKind kind;

  /// The file system keeps a recycle bin (not FAT or exFAT).
  final bool hasTrash;

  /// How it was decided, for the merge screen's tooltip.
  final String reason;

  const DriveInfo(this.kind, {this.hasTrash = false, this.reason = ''});

  bool get trashSafe => kind == DriveKind.internal && hasTrash;
}

typedef _GetDriveTypeN = Uint32 Function(Pointer<Utf16>);
typedef _GetDriveTypeD = int Function(Pointer<Utf16>);
typedef _GetVolInfoN = Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Uint32>, Pointer<Uint32>,
    Pointer<Uint32>, Pointer<Utf16>, Uint32);
typedef _GetVolInfoD = int Function(
    Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Utf16>, int);

const _driveRemovable = 2, _driveFixed = 3, _driveRemote = 4, _driveCdRom = 5;

/// Looks up the drive holding [folder]. Windows only for now; other systems
/// answer unknown, which offers Delete permanently only.
Future<DriveInfo> driveInfoFor(String folder) async {
  if (!Platform.isWindows) return const DriveInfo(DriveKind.unknown, reason: 'not checked on this system');
  if (folder.startsWith(r'\\')) return const DriveInfo(DriveKind.network, reason: 'network share');
  final root = p.rootPrefix(folder);
  if (!RegExp(r'^[A-Za-z]:\\?$').hasMatch(root)) return const DriveInfo(DriveKind.unknown, reason: 'no drive letter');
  final letter = root.substring(0, 1).toUpperCase();

  final (type, fs) = await Isolate.run(() => _query('$letter:\\'));
  if (type == _driveRemote) return const DriveInfo(DriveKind.network, reason: 'network drive');
  if (type == _driveRemovable || type == _driveCdRom) {
    return const DriveInfo(DriveKind.removable, reason: 'removable drive');
  }
  if (type != _driveFixed) return const DriveInfo(DriveKind.unknown, reason: 'drive type unknown');
  final hasTrash = fs != null && !fs.toUpperCase().contains('FAT');

  // Windows reports many USB disks as fixed; the bus they're on tells.
  final bus = await _busType(letter);
  if (bus == null) return DriveInfo(DriveKind.unknown, hasTrash: hasTrash, reason: 'connection unknown');
  if (const {'USB', 'SD', 'MMC', '1394', 'Thunderbolt'}.contains(bus)) {
    return DriveInfo(DriveKind.removable, hasTrash: hasTrash, reason: '$bus drive');
  }
  return DriveInfo(DriveKind.internal, hasTrash: hasTrash, reason: '$bus drive, ${fs ?? 'unknown file system'}');
}

(int, String?) _query(String root) {
  final k32 = DynamicLibrary.open('kernel32.dll');
  final getType = k32.lookupFunction<_GetDriveTypeN, _GetDriveTypeD>('GetDriveTypeW');
  final getVol = k32.lookupFunction<_GetVolInfoN, _GetVolInfoD>('GetVolumeInformationW');
  final path = root.toNativeUtf16();
  final fsName = calloc<Uint16>(64).cast<Utf16>();
  try {
    final type = getType(path);
    final ok = getVol(path, nullptr, 0, nullptr, nullptr, nullptr, fsName, 64);
    return (type, ok != 0 ? fsName.toDartString() : null);
  } finally {
    calloc.free(path);
    calloc.free(fsName);
  }
}

/// The disk's bus type (SATA, NVMe, USB...), or null when it can't be read.
Future<String?> _busType(String letter) async {
  try {
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      '(Get-Partition -DriveLetter $letter | Get-Disk).BusType',
    ]).timeout(const Duration(seconds: 10));
    final out = '${r.stdout}'.trim();
    return r.exitCode == 0 && out.isNotEmpty ? out : null;
  } catch (_) {
    return null;
  }
}

/// Sends [folder] to the Recycle Bin. Only call it when [DriveInfo.trashSafe].
///
/// Uses Windows' own file operation, owned by the app's window, so a prompt
/// it shows opens in front of the app. It asks nothing for an ordinary
/// folder; for one too big for the Recycle Bin, Windows asks before deleting
/// it permanently, and No keeps it.
Future<void> moveToTrash(String folder) async {
  final owner = _appWindow();
  final (code, aborted) = await Isolate.run(() => _shellDelete(folder, owner));
  if (aborted) throw FileSystemException('Cancelled. Nothing was deleted.', folder);
  if (code != 0 || Directory(folder).existsSync()) {
    throw FileSystemException('Could not move it to the Recycle Bin (Windows error $code).', folder);
  }
}

// SHFileOperationW flags.
const _foDelete = 0x0003;
const _fofSilent = 0x0004; // no progress window
const _fofNoConfirmation = 0x0010; // no "are you sure?" for ordinary folders
const _fofAllowUndo = 0x0040; // to the Recycle Bin
const _fofNoConfirmMkdir = 0x0200;
const _fofWantNukeWarning = 0x4000; // but do ask before a permanent delete

final class _ShFileOp extends Struct {
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int wFunc;
  external Pointer<Utf16> pFrom;
  external Pointer<Utf16> pTo;
  @Uint16()
  external int fFlags;
  @Int32()
  external int fAnyOperationsAborted;
  external Pointer<Void> hNameMappings;
  external Pointer<Utf16> lpszProgressTitle;
}

typedef _ShFileOpN = Int32 Function(Pointer<_ShFileOp>);
typedef _ShFileOpD = int Function(Pointer<_ShFileOp>);
typedef _FindWindowN = IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>);
typedef _FindWindowD = int Function(int, int, Pointer<Utf16>, Pointer<Utf16>);
typedef _WindowPidN = Uint32 Function(IntPtr, Pointer<Uint32>);
typedef _WindowPidD = int Function(int, Pointer<Uint32>);

/// This app's main window, or 0 when it can't be found (then Windows'
/// prompt has no owner, but still works).
int _appWindow() {
  if (!Platform.isWindows) return 0;
  try {
    final user32 = DynamicLibrary.open('user32.dll');
    final findEx = user32.lookupFunction<_FindWindowN, _FindWindowD>('FindWindowExW');
    final windowPid = user32.lookupFunction<_WindowPidN, _WindowPidD>('GetWindowThreadProcessId');
    final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final owner = calloc<Uint32>();
    try {
      var h = 0;
      while ((h = findEx(0, h, cls, nullptr)) != 0) {
        windowPid(h, owner);
        if (owner.value == pid) return h;
      }
    } finally {
      calloc.free(cls);
      calloc.free(owner);
    }
  } catch (_) {}
  return 0;
}

/// Runs on a background isolate, so the app keeps drawing while a big folder
/// is moved. Returns Windows' result code and whether the user said No.
(int, bool) _shellDelete(String folder, int owner) {
  final shell32 = DynamicLibrary.open('shell32.dll');
  final op = shell32.lookupFunction<_ShFileOpN, _ShFileOpD>('SHFileOperationW');
  // The path list ends with two nulls.
  final units = p.normalize(folder).codeUnits;
  final from = calloc<Uint16>(units.length + 2);
  for (var i = 0; i < units.length; i++) {
    from[i] = units[i];
  }
  final info = calloc<_ShFileOp>();
  try {
    info.ref
      ..hwnd = owner
      ..wFunc = _foDelete
      ..pFrom = from.cast()
      ..pTo = nullptr
      ..fFlags = _fofSilent | _fofNoConfirmation | _fofAllowUndo | _fofNoConfirmMkdir | _fofWantNukeWarning;
    final code = op(info);
    return (code, info.ref.fAnyOperationsAborted != 0);
  } finally {
    calloc.free(from);
    calloc.free(info);
  }
}

