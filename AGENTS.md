# AGENTS.md

## Project knowledge graph (PREFERRED over grepping source)

This repo has a prebuilt **graphify** knowledge graph at `graphify-out/`.

**Use the graph FIRST for any codebase question before reading source files:**

- `graphify-out/GRAPH_REPORT.md` — architecture overview: communities, god nodes, import cycles, suggested questions.
- `graphify-out/graph.json` — raw graph (nodes + edges: defines/extends/imports/calls/handles_signal).
- `graphify-out/graph.html` — interactive visualization (open in browser).

Query it with:

```powershell
graphify query "<question>"
```

Fallback (if `graphify` CLI unavailable): read `graphify-out/graph.json` directly and traverse it in Python.

### Node ID convention
File nodes: lowercase path with `_` separators (e.g. `scripts_entities_player`). Function nodes: `<file_id>_<funcname>`. Signal nodes: `<file_id>_<signalname>`. Builtin Godot classes: `godot_<class>` (e.g. `godot_characterbody3d`).

### Important: GDScript is extracted with a CUSTOM extractor
graphify has NO native GDScript (.gd) AST extractor. This project uses `graphify-out/build_graph.py`, which parses GDScript and produces graphify-compatible JSON.

**Regenerate the graph after significant changes** (new files, refactors):

```powershell
python graphify-out/build_graph.py
```

This rewrites `graphify-out/graph.json`, `GRAPH_REPORT.md`, `graph.html`. Uses the Python interpreter at `graphify-out/.graphify_python` (graphify's venv).

## Project layout
- `scripts/` — main game code (core, entities, objects, ui)
- `scenes/` — Godot scenes
- `addons/local_keep_ai/` — LocalKeep AI plugin (lk_client, lk_dock, plugin)
- `ziva_installer/` — installer plugin (downloads, ui)
- `resources/` — passive data resources
