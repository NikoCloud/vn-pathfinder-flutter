import 'package:flutter/widgets.dart';

/// The app's keyboard focus when no text field has it, so shortcuts keep
/// working after clicking around the library.
final shellFocus = FocusNode(debugLabel: 'shell');
