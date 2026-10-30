import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/game_status.dart';
import '../../theme.dart';

/// Colour for "update available" badges — distinct from the status colours
/// (Updated = installed but unplayed; this = newer on a forum, not downloaded).
const updateAvailableColor = Color(0xFFFFC857);

/// Icon and colour for each status — shared by the status dropdown, the game
/// context menu and anything else that shows a status.
IconData statusIcon(GameStatus s) => switch (s) {
      GameStatus.unplayed => Icons.circle_outlined,
      GameStatus.playing => Icons.play_circle_outline,
      GameStatus.updated => Icons.new_releases_outlined,
      GameStatus.onHold => Icons.pause_circle_outline,
      GameStatus.completed => Icons.check_circle_outline,
      GameStatus.skimmed => Icons.fast_forward_outlined,
      GameStatus.abandoned => Icons.do_not_disturb_on_outlined,
    };

Color statusColor(GameStatus s) => switch (s) {
      GameStatus.unplayed => AppColors.textMuted,
      GameStatus.playing => AppColors.playGreen,
      GameStatus.updated => Colors.lightBlueAccent,
      GameStatus.onHold => Colors.orange,
      GameStatus.completed => AppColors.accent,
      GameStatus.skimmed => Colors.purpleAccent,
      GameStatus.abandoned => AppColors.danger,
    };

/// Menu entries for setting a game's status. Values are GameStatus ids, or ''
/// for "Auto" (clear the pick and let the status be detected). [detected] is
/// what Auto currently resolves to; [picked] is the user's current choice.
List<PopupMenuEntry<String>> statusMenuEntries({
  required GameStatus detected,
  GameStatus? picked,
}) {
  PopupMenuItem<String> item(String value, IconData icon, Color color, String label,
          {String? hint, bool selected = false}) =>
      PopupMenuItem<String>(
        value: value,
        height: 36,
        child: Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 10),
          Text(label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              )),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Text(hint, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
          ],
          if (selected) ...[
            const SizedBox(width: 10),
            const Icon(Icons.check, size: 14, color: AppColors.accent),
          ],
        ]),
      );

  return [
    item('', Icons.auto_awesome_outlined, AppColors.textSecondary, 'Auto',
        hint: '(${detected.label})', selected: picked == null),
    const PopupMenuDivider(height: 1),
    for (final s in GameStatus.manual)
      item(s.id, statusIcon(s), statusColor(s), s.label, selected: picked == s),
  ];
}
