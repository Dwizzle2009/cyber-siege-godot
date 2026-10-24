# Aeon SDK — Godot 4 addon

Copy `addons/aeon_sdk` into your project, enable it in Project → Plugins. It registers an
autoload named **Aeon**. Pure GDScript; no native build; works in the editor as a no-op.

```gdscript
Aeon.unlock("first_win")
Aeon.progress("collector", 3, 10)
Aeon.submit_score("score", 1234)
Aeon.set_presence("Wave 7 - Night City")
if Aeon.owns("CYBER-SIEGE-ARENA-SP1"): show_season_pass_content()

Aeon.leaderboard_received.connect(func(cat, entries, my_rank, my_score, has_me): ...)
Aeon.get_leaderboard("score", 10)

Aeon.purchase_result.connect(func(sku, completed): ...)
Aeon.purchase("CYBER-SIEGE-ARENA-SP1")   # the console shows the purchase UI
```

`Aeon.is_on_aeon()` is true only on a console with a live session; `Aeon.player` has `id`, `gamertag`, `lang`.
Reports are queued, retried, and kept in `user://aeon_queue.jsonl` across launches when offline.
