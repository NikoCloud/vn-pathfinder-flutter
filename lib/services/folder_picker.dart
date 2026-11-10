import 'package:file_selector/file_selector.dart';

/// Asks the user to choose a folder. Null when they cancel. [title] is kept
/// for callers' readability; file_selector has no dialog title on Windows.
///
/// Uses file_selector, not file_picker. file_picker's folder dialog runs on
/// the main Dart thread and holds it until the dialog closes. Anything that
/// finished meanwhile, such as a library scan started by the folder just
/// added, then crashed the app inside Windows' dialog code. file_selector
/// opens the dialog from native code, so the app keeps running behind it.
Future<String?> pickFolder(String title) =>
    getDirectoryPath(confirmButtonText: 'Select Folder');
