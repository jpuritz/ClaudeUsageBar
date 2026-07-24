Claudar app icon kit (v4: dark squircle)
========================================

Files
-----
claudar-icon-dark-1024.png         master icon — THIS IS THE SHIPPED ONE
claudar-icon-1024.png              light variant (paper squircle), kept for reference
claudar-mark-transparent-1024.png  the radar mark alone, transparent background
claudar-mark.svg                   editable vector master of the mark
Claudar.iconset/                   all 10 sizes macOS needs, generated from the dark master

Regenerating the shipped icon
-----------------------------
`Resources/AppIcon.icns` is what both build paths copy into the bundle. To
rebuild it after editing the master:

    python3 - <<'PY'
    from PIL import Image
    src = Image.open("design/claudar-icon-dark-1024.png").convert("RGBA")
    for px, name in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),
                     (128,"128x128"),(256,"128x128@2x"),(256,"256x256"),
                     (512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")]:
        src.resize((px,px), Image.LANCZOS).save(f"design/Claudar.iconset/icon_{name}.png")
    PY
    iconutil -c icns design/Claudar.iconset -o Resources/AppIcon.icns

The website favicons come from the same master:
`docs/favicon-32.png` (32×32) and `docs/apple-touch-icon.png` (180×180).

Notes
-----
- The dark squircle is the shipped icon on purpose: at favicon sizes the green
  ring holds far more contrast against black than the paper version did, and it
  matches the app's own dark UI and the og-card.
- The two radar contacts are a Claude-style spark (upper right, just caught by
  the sweep) and a little Claude Code bot (lower left), both in Claude orange
  #D97757. Radar stays green so the contacts read as detections.
- The squircle uses Apple's standard margins (content is 824/1024 of the canvas),
  so it sits at the same visual size as other Dock icons.
- Colors: radar green #7FB98E on #191916 (shipped), #3D7B52 on paper #FAF9F6
  (light variant); blips #D97757 in both.
- The geometry matches the animated logo on the claudarapp.com landing page,
  which uses the same orange for its blips.
