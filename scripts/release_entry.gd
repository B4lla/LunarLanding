extends Node
## F07 native exported release dispatcher. No physics or TCP code lives here.
## Godot release templates do not necessarily support the editor-only --scene
## override, so a portable release uses OS user args after the -- separator.

func _ready() -> void:
    # remote.tscn embeds main.tscn as Simulation. Its nested instance must NOT
    # replace the remote scene or start an infinite scene change loop.
    var main_root: Node = get_parent()
    if main_root == null or main_root.get_parent() != get_tree().root:
        return
    if not OS.get_cmdline_user_args().has("--rl-remote"):
        return
    print("F07_REMOTE_BOOT: loading res://scenes/remote.tscn")
    # Defer replacement until the starting scene has finished entering the tree.
    get_tree().call_deferred("change_scene_to_file", "res://scenes/remote.tscn")
