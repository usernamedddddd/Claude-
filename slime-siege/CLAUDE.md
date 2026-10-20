# Slime Siege: working rules for Claude

- **UI designs go through the Figma connector.** Design or redesign any UI (HUD, tower panel,
  lobby, shop, results, menus) in Figma first using the Figma connector, then implement it in
  `src/client/Controllers` from that design. If the Figma connector is unavailable, say so and
  ask before falling back to designing in code.
- **Do not update Google Drive.** Progress notes go in `README.md` in this repo instead.
- Before pushing: `stylua src tests tools`, strict `luau-lsp analyze`, `lune run tools/test`,
  `lune run tools/smoke` (see README).
