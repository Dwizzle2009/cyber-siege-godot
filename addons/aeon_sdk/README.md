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

## 1.1: identity, console events, display

```gdscript
# in-game display: the console draws a disc in avatar_color with the gamertag's first letter; do the same
$NameLabel.text = Aeon.player.gamertag
$Avatar.modulate = Color(Aeon.player.avatar_color)

# the Guide covering the game, and the console going to rest and waking
Aeon.guide_opened.connect(func(): get_tree().paused = true)
Aeon.guide_closed.connect(func(): get_tree().paused = false)
Aeon.resumed.connect(func(): _resync_clock())      # suspended fires right before it; the process was frozen

# what the console launched on, for a frame-rate policy
var d := Aeon.display()                              # { refresh_hz: 120, vrr: true, output: "2560x1440" }
Engine.max_fps = 0 if d.vrr else d.refresh_hz
```

`Aeon.is_guide_open()` answers at any time. Events come from a small file the shell rewrites
(`AEON_STATE`), polled ten times a second from `_process`, so they arrive on the main thread with at most
100 ms of latency. Off-Aeon nothing fires and `display()` is zeros.
