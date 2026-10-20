# Slime Siege: working rules for Claude

- **All design work goes through the Figma connector.** Any design (UI screens, HUD, menus,
  icons, logos, thumbnails, store art, map layouts, tower/slime concept art, diagrams) is made
  or iterated in Figma first, then implemented from that design. If the Figma connector is
  unavailable, say so and ask before designing any other way.
- **Do not update Google Drive.** Progress notes go in `README.md` in this repo instead.
- Before pushing: `stylua src tests tools`, strict `luau-lsp analyze`, `lune run tools/test`,
  `lune run tools/smoke` (see README).
