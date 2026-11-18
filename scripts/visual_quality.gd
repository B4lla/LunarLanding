extends Node
## F14 runtime-only visual quality tuning.
## Applies anti-aliasing and mild viewport postprocessing without touching
## project.godot or any simulation contract.

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var viewport := get_viewport()
    if viewport == null:
        return
    # MSAA works with the project's GL Compatibility renderer. FXAA, TAA and
    # debanding do not (Godot renderer support matrix): do not present their
    # unsupported flags as operational graphics enhancements.
    # F37: 2x default reduces the MSAA render-target/bandwidth cost in GL.
    # Opt in to the old 4x profile only for screenshot-quality comparisons.
    viewport.msaa_3d = Viewport.MSAA_4X if OS.get_environment("ROCKET_F37_MSAA").to_lower() == "4x" else Viewport.MSAA_2X
    var rendering_method: String = str(ProjectSettings.get_setting(
        "rendering/renderer/rendering_method", "gl_compatibility"))
    if rendering_method == "gl_compatibility":
        viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
        viewport.use_taa = false
        viewport.use_debanding = false
    elif rendering_method == "gl_compatibility_mobile":
        # Defensive alias: no unsupported post-processing if a GL variant is used.
        viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
        viewport.use_taa = false
        viewport.use_debanding = false
    elif rendering_method == "mobile":
        viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
        viewport.use_taa = false
        viewport.use_debanding = true
    else:
        # Forward+ supports temporal AA and debanding. Avoid stacking FXAA.
        viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
        viewport.use_taa = true
        viewport.use_debanding = true
