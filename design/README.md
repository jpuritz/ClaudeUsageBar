Claudar app icon kit (v3: Claude-orange blips)
==============================================

Files
-----
claudar-icon-1024.png              master icon, light (paper squircle, radar green)
claudar-icon-dark-1024.png         dark variant (for macOS dark mode icons, optional)
claudar-mark-transparent-1024.png  the radar mark alone, transparent background
claudar-mark.svg                   editable vector master of the mark
Claudar.iconset/                   all 10 sizes macOS needs, pre-generated

Make the .icns (run on your Mac)
--------------------------------
cd into this folder, then:

    iconutil -c icns Claudar.iconset

That produces Claudar.icns. In Xcode, either drop the .icns into your target's
Asset Catalog (AppIcon) or drag the individual PNGs from Claudar.iconset into
the AppIcon slots.

Notes
-----
- The two radar contacts are a Claude-style spark (upper right, just caught by
  the sweep) and a little Claude Code bot (lower left), both in Claude orange
  #D97757. Radar stays green so the contacts read as detections.
- The squircle uses Apple's standard margins (content is 824/1024 of the canvas),
  so it sits at the same visual size as other Dock icons.
- Colors: radar green #3D7B52 on paper #FAF9F6 (light), #7FB98E on #191916 (dark);
  blips #D97757 in both.
- The geometry matches the animated logo on the claudarapp.com landing page,
  which uses the same orange for its blips.
