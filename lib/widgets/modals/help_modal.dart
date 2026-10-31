import 'package:flutter/material.dart';
import '../../theme.dart';

void showHelpModal(BuildContext context) {
  showDialog<void>(context: context, builder: (_) => const _HelpModal());
}

const _sections = <(String, List<(String, String)>)>[
  ('Getting started', [
    ('Library folder', 'Settings → General. Each game goes in its own folder inside it.'),
    ('Going online', 'Lockdown Mode is on by default, so nothing goes online. Turn it off in Settings → Network.'),
    ('Forum logins', 'Settings → Network. Log in through the built-in browser.'),
    ('Game details', 'Select a game and choose Fetch Metadata. Pick each field from any source.'),
  ]),
  ('Keyboard shortcuts', [
    ('↑ ↓', 'Move through the game list'),
    ('Enter', 'Play the selected game'),
    ('Ctrl + ,', 'Open Settings'),
    ('F1', 'Open this help'),
    ('Ctrl+K', 'Find a game, in your library or on the Feed'),
    ('Ctrl+Shift+D', 'Discreet: blur all art'),
    ('← →  Esc', 'Full-screen images: previous, next, close'),
  ]),
  ('Game status', [
    ('Automatic', 'Worked out from save files and play history. Only autosaves means Skimmed.'),
    ('Your choice', "Change it under Your copy on a game's page, or from the right-click menu. Auto hands it back."),
  ]),
  ('Duplicates', [
    ('Merging', 'Right-click a game and choose Merge into Another Game. Your files stay where they are.'),
    ('Undoing it', 'Properties → Versions → Separate.'),
  ]),
  ('Mods', [
    ('Assigning', 'Archive tab: right-click an archive and choose Assign. A file can be a patch for a game, or take saved game data, for example after you rename a download.'),
    ('Turning on and off', 'Properties → Patches. Nothing is deleted.'),
  ]),
  ('LewdCorner', [
    ('Plus games', 'Plus and AI+ games need a forum role. Without it, the forum hides their images.'),
    ('Small images', 'LewdCorner no longer serves some older full-size files. Pathfinder uses another source when it can confirm the same game, and otherwise saves thumbnails.'),
  ]),
];

class _HelpModal extends StatelessWidget {
  const _HelpModal();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderMd,
        side: BorderSide(color: AppColors.border),
      ),
      child: SizedBox(
        width: 560,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Help',
                        style: AppText.ui(
                            fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: Icon(Icons.close, size: 16, color: AppColors.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                children: [
                  for (final (title, rows) in _sections) ...[
                    Text(title,
                        style: AppText.ui(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent)),
                    const SizedBox(height: 8),
                    for (final (name, text) in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 130,
                              child: Text(name,
                                  style: AppText.ui(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimary)),
                            ),
                            Expanded(
                              child: Text(text,
                                  style: AppText.ui(
                                      fontSize: 12, height: 1.4, color: AppColors.textSecondary)),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
