extends Node
## F19: onboard/telemetry sound, NOT acoustics travelling through lunar vacuum.
## Purely presentational: only reads input, state and impact telemetry.
## F37 loads optional broadband, seamless sound beds, preserving F19 source WAVs.
## F40: reliable throttle onset, WAV-import fallbacks and live engine telemetry.
## F41: keep main-engine loops alive across RCS commands and expose episode/mix state.
## F42: explicit full-sample loops and detect/recover stalled motor transport.
## Audio is inert when Godot uses the headless display server.

@onready var rocket: RocketPhysics = get_node("../Rocket")
@onready var episode: EpisodeController = get_node("../EpisodeController")

# Preserve F08/F09 public names, sliders, and original WAV hashes.
var engine: AudioStreamPlayer
var rcs: AudioStreamPlayer
var touchdown: AudioStreamPlayer

var engine_turbine: AudioStreamPlayer
var engine_ignition: AudioStreamPlayer
var engine_cutoff: AudioStreamPlayer
var rcs_hiss: AudioStreamPlayer
var rcs_pulse: AudioStreamPlayer
var landing_gear: AudioStreamPlayer
var crash: AudioStreamPlayer
var landing_confirm: AudioStreamPlayer
var audio_test_player: AudioStreamPlayer

const F37_AUDIO_DIR: String = "res://assets/audio_legacy/"
const F38_AUDIO_DIR: String = "res://assets/audio_enhanced/"
const F39_AUDIO_DIR: String = "res://assets/audio_fire/"
const ENGINE_HEADROOM_DB: float = 3.0

var _mix_muted: bool = false
var _master_level: float = 1.0
var _engine_level: float = 1.0
var _rcs_level: float = 1.0
var _touchdown_level: float = 1.0
var _previous_terminal: bool = false
var _previous_contact: bool = false
var _previous_throttle: float = 0.0
var _previous_rcs: Vector3 = Vector3.ZERO
var _rcs_burst_cooldown: float = 0.0
var _last_elapsed: float = 0.0
var _loaded_audio_paths: Dictionary = {}
var _live_throttle: float = 0.0
var _engine_watchdog_restarts: int = 0
var _engine_transport_stalls: Dictionary = {}
var _engine_transport_positions: Dictionary = {}
var _engine_stall_recoveries: int = 0
var _engine_unpause_recoveries: int = 0
var _last_rcs_event_detail: String = "no RCS"


# F25.2: diagnosis that does not require a running engine, an RCS command or a landing.
# -1 = normal telemetry audio; 0..2 = deliberate independent audition.
var _audio_test_step: int = -1
var _audio_test_remaining: float = 0.0
var _audio_test_note: String = "No test started"


func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        set_process(false)
        return
    # New, original, bundled sound assets; F08 WAVs remain byte-identical.
    engine = _make_player("MainEngineAudio", "res://assets/audio/engine_rumble.wav", true, -55.0)
    engine_turbine = _make_player("EngineTurbineAudio", "res://assets/audio/engine_turbine.wav", true, -55.0)
    engine_ignition = _make_player("EngineIgnitionAudio", "res://assets/audio/engine_ignition.wav", false, -16.0)
    engine_cutoff = _make_player("EngineCutoffAudio", "res://assets/audio/engine_cutoff.wav", false, -19.0)
    rcs = _make_player("RCSAudio", "res://assets/audio/rcs.wav", true, -55.0)
    rcs_hiss = _make_player("RCSSteeringHissAudio", "res://assets/audio/rcs_hiss.wav", true, -55.0)
    rcs_pulse = _make_player("RCSValvePulseAudio", "res://assets/audio/rcs_pulse.wav", false, -16.0)
    touchdown = _make_player("TouchdownAudio", "res://assets/audio/touchdown.wav", false, -18.0)
    landing_gear = _make_player("LandingGearContactAudio", "res://assets/audio/landing_gear.wav", false, -14.0)
    crash = _make_player("CrashAudio", "res://assets/audio/crash.wav", false, -9.0)
    landing_confirm = _make_player("LandingConfirmAudio", "res://assets/audio/landing_confirm.wav", false, -19.0)
    # Engine beds are long-lived, independent players. Playing a steering/RCS
    # one-shot must never force them to restart or share a player/stream slot.
    # Start silent: the throttle envelope, not an input edge, controls audibility.
    for bed in [engine, engine_turbine]:
        if bed.stream != null:
            bed.volume_db = -80.0
            bed.play()
    # Dedicated preview bus: testing the speakers must never consume the real
    # touchdown or ignition events, even if the rocket is currently flying.
    audio_test_player = AudioStreamPlayer.new()
    audio_test_player.name = "AudioDiagnostic"
    audio_test_player.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(audio_test_player)
    var loaded: int = 0
    for player in _all_players():
        if player != null and player.stream != null:
            loaded += 1
    if loaded != _all_players().size():
        push_warning("F25.2 AUDIO: only %d/%d WAV files loaded. Reimport the project." %
            [loaded, _all_players().size()])
    print("F25.2 AUDIO: %d/%d WAV files loaded, driver=%s" %
        [loaded, _all_players().size(), AudioServer.get_driver_name()])


func configure_mix(muted: bool, master: float, engine_gain: float,
        rcs_gain: float, touchdown_gain: float) -> void:
    _mix_muted = muted
    _master_level = clampf(master, 0.0, 1.0)
    _engine_level = clampf(engine_gain, 0.0, 1.0)
    _rcs_level = clampf(rcs_gain, 0.0, 1.0)
    _touchdown_level = clampf(touchdown_gain, 0.0, 1.0)
    # F09: mute and zero-volume sliders must silence immediately, not after a fade.
    if _mix_muted or _master_level < 0.001:
        _stop_players(_all_players())
        return
    if _engine_level < 0.001:
        _stop_players([engine, engine_turbine, engine_ignition, engine_cutoff])
    if _rcs_level < 0.001:
        _stop_players([rcs, rcs_hiss, rcs_pulse])
    if _touchdown_level < 0.001:
        _stop_players([touchdown, landing_gear, crash, landing_confirm])


func _all_players() -> Array:
    return [engine, engine_turbine, engine_ignition, engine_cutoff,
        rcs, rcs_hiss, rcs_pulse, touchdown, landing_gear, crash, landing_confirm]


func _stop_players(players: Array) -> void:
    for player in players:
        if player != null and player.playing:
            player.stop()


func _make_player(name: String, path: String, looping: bool, initial_db: float) -> AudioStreamPlayer:
    var player := AudioStreamPlayer.new()
    player.name = name
    # F40: resolve each candidate by actually loading it. ResourceLoader.exists()
    # can be true while the new WAV import is still missing or invalid; the old
    # code selected that unplayable path without trying a known-working sound.
    # F39's PCM WAV import is bundled; F38/F37/F19 remain safe fallbacks.
    var filename: String = path.get_file()
    var candidates: Array[String] = [
        F39_AUDIO_DIR + filename, F38_AUDIO_DIR + filename,
        F37_AUDIO_DIR + filename, path,
    ]
    var stream: AudioStreamWAV = null
    var source: String = ""
    for candidate in candidates:
        if not ResourceLoader.exists(candidate):
            continue
        stream = load(candidate) as AudioStreamWAV
        if stream != null:
            source = candidate
            break
    if stream == null:
        push_warning("F40 AUDIO: could not load any source for " + path)
    else:
        if looping:
            # Both ends must be defined: a stale imported loop_end=0 may
            # start playing normally and become silent at the sample boundary.
            stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
            stream.loop_begin = 0
            stream.loop_end = -1
        player.stream = stream
    _loaded_audio_paths[name] = source
    player.volume_db = initial_db
    player.bus = "Master"
    player.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(player)
    return player

func _process(delta: float) -> void:
    if engine == null or rcs == null or touchdown == null:
        return
    if _audio_test_step >= 0:
        _advance_audio_test(maxf(delta, 0.0))
    var dt: float = maxf(delta, 0.0)
    var terminal: bool = episode.is_finished()
    var paused: bool = get_tree().paused
    var enabled: bool = not paused and not terminal
    var throttle: float = clampf(rocket.throttle, 0.0, 1.0) if enabled else 0.0
    _live_throttle = throttle
    var rcs_command := Vector3(rocket.gimbal_x, rocket.gimbal_z, rocket.yaw_rcs) if enabled else Vector3.ZERO
    var rcs_level: float = clampf(maxf(absf(rcs_command.x),
        maxf(absf(rcs_command.y), absf(rcs_command.z))), 0.0, 1.0)
    _rcs_burst_cooldown = maxf(0.0, _rcs_burst_cooldown - dt)

    # Detect reset even when the episode uses the same seed.
    var restarted: bool = (episode.elapsed_s + 0.025 < _last_elapsed) or (
        _previous_terminal and not terminal)
    if restarted:
        _engine_transport_stalls.clear()
        _engine_transport_positions.clear()
        _stop_players([touchdown, landing_gear, crash, landing_confirm,
            engine_ignition, engine_cutoff, rcs_pulse])
        _previous_contact = false
        _previous_throttle = 0.0
        _previous_rcs = Vector3.ZERO
        _rcs_burst_cooldown = 0.0

    # Continuous layers provide convincing throttle tracking without restarting loops.
    # F25.2: reinforce the audible midrange turbine, since the deep rumble
    # contains most of its energy below 70 Hz (invisible to small speakers).
    # F38: broad-band chamber rumble must be clearly audible on ordinary PC
    # speakers even at partial throttle; no artificial engine while throttle=0.
    # F40: a continuous combustion bed whose actual volume follows the
    # commanded throttle every frame. A perceptual curve retains audible
    # low-throttle vibration and still makes 25/50/75/100% distinguishable.
    # Keep the louder chamber pressure and quieter high-frequency exhaust
    # as two separate layers, without turning WASD/RCS into the main engine.
    _update_loop(engine, throttle, 0.0, _engine_level, dt)
    _update_loop(engine_turbine, throttle, -3.0, _engine_level, dt)
    # RCS remains a lower-volume, separate pair of players: it should be heard
    # as steering jets without masking the sustained thrust bed.
    _update_loop(rcs, rcs_level, -15.0, _rcs_level * 0.55, dt)
    _update_loop(rcs_hiss, rcs_level, -5.0, _rcs_level * 0.55, dt)
    # Broad noise should remain a roar/hiss, not become a pitched ticking loop.
    # Engine pitch shifts very slightly with commanded thrust, avoiding
    # cartoon-like RPM jumps on an actual rocket combustion chamber.
    engine.pitch_scale = 0.88 + 0.16 * throttle
    engine_turbine.pitch_scale = 0.90 + 0.19 * throttle
    rcs.pitch_scale = 1.0
    rcs_hiss.pitch_scale = 0.99 + 0.03 * rcs_level

    var first_terminal: bool = terminal and not _previous_terminal
    if not paused and not first_terminal:
        # F40: rising/falling edge at the *same* threshold. The F39 condition
        # demanded an impossible 3.5% -> 7.5% jump at ordinary 60 FPS when
        # the Up arrow changes thrust at just 0.4/s, skipping ignition.
        if throttle > 0.02 and _previous_throttle <= 0.02:
            _play_one_shot(engine_ignition, -8.0, _engine_level)
        if throttle <= 0.02 and _previous_throttle > 0.02:
            _play_one_shot(engine_cutoff, -11.0, _engine_level)

        # The old F08 RCS loop used only yaw. F19 listens to ALL W/A/S/D/Q/E
        # gimbal/yaw commands; a transient hiss fires on starts or reversals.
        var new_command: bool = rcs_level > 0.12 and _previous_rcs.length() <= 0.10
        var reversal: bool = rcs_level > 0.12 and _previous_rcs.length() > 0.10 \
            and rcs_command.dot(_previous_rcs) < -0.15
        if (new_command or reversal) and _rcs_burst_cooldown <= 0.0:
            rcs_pulse.pitch_scale = 1.0
            _play_one_shot(rcs_pulse, -21.0, _rcs_level)
            _rcs_burst_cooldown = 0.16
            # Capture the actual flight state at the instant steering begins.
            # It is crucial to distinguish an audio interruption from a crash
            # (EpisodeController disables throttle and freezes a finished flight).
            _last_rcs_event_detail = "%.0f%% throttle, %s" % [
                throttle * 100.0, episode.result_name()]

    var contact_now: bool = rocket.contact_platform or rocket.contact_ground
    var first_contact: bool = contact_now and not _previous_contact
    if not paused:
        if first_terminal and episode.result == EpisodeController.Result.CRASH:
            # Crash wins if an excessive-speed contact is already terminal.
            _stop_players([touchdown, landing_gear, landing_confirm])
            var impact_speed: float = episode.impact_velocity.length()
            var severity: float = clampf(impact_speed / 8.0, 0.25, 1.0)
            crash.pitch_scale = 0.94 + 0.10 * severity
            _play_one_shot(crash, -7.0 + 4.0 * severity, _touchdown_level)
        elif first_contact:
            var velocity: float = rocket.initial_contact_velocity.length()
            var contact_weight: float = clampf(velocity / 3.5, 0.16, 1.0)
            landing_gear.pitch_scale = 0.95 + 0.08 * contact_weight
            _play_one_shot(landing_gear, -10.0 + 4.0 * contact_weight,
                _touchdown_level)
            touchdown.volume_db = -12.0 + 4.0 * contact_weight + \
                linear_to_db(maxf(_master_level * _touchdown_level, 0.001))
            _play_one_shot(touchdown, -12.0 + 4.0 * contact_weight, _touchdown_level)
        if first_terminal and episode.result == EpisodeController.Result.LANDED:
            _play_one_shot(landing_confirm, -10.0, _touchdown_level)

    # Keep engine players independent from everything that ran in RCS handlers.
    # AudioStreamPlayer.playing is a transport check; if the driver stops a voice
    # unexpectedly while thrust is active, recover without requiring a new
    # ignition edge or releasing WASD.
    if enabled and throttle > 0.015 and not _mix_muted \
            and _master_level * _engine_level >= 0.001:
        _restore_engine_voice(engine, throttle, 0.0)
        _restore_engine_voice(engine_turbine, throttle, -3.0)
        _check_engine_transport(engine, throttle, 0.0, dt)
        _check_engine_transport(engine_turbine, throttle, -3.0, dt)
    else:
        # Never treat an intentional pause, idle, or terminal stop as a stall.
        _engine_transport_positions.clear()
        _engine_transport_stalls.clear()

    # Paused scenes and finished episodes stop the transport explicitly.
    # A *finished episode* cannot resume thrust without R/N reset by design.
    if paused:
        _stop_players(_all_players())
    elif terminal:
        # Never kill the crash/touchdown one-shots triggered just above.
        _stop_players([engine, engine_turbine, rcs, rcs_hiss, rcs_pulse])

    _previous_throttle = throttle
    _previous_rcs = rcs_command
    _previous_contact = contact_now
    _previous_terminal = terminal
    _last_elapsed = episode.elapsed_s


func _play_one_shot(player: AudioStreamPlayer, peak_db: float, channel_gain: float) -> void:
    if player == null or player.stream == null:
        return
    var gain: float = _master_level * channel_gain
    if _mix_muted or gain < 0.001:
        return
    player.volume_db = peak_db + linear_to_db(gain)
    player.play()


func _update_loop(player: AudioStreamPlayer, level: float, peak_db: float,
        channel_gain: float, delta: float) -> void:
    if player == null or player.stream == null:
        return
    var gain: float = _master_level * channel_gain
    if _mix_muted or gain < 0.001:
        if player.playing:
            player.stop()
        return
    var is_engine_bed: bool = player == engine or player == engine_turbine
    # F42: leave mixing headroom at full throttle; two simultaneous 0 dB
    # layers can clip the Master bus before any RCS or impact one-shot.
    var audible_peak: float = peak_db + linear_to_db(gain) - (ENGINE_HEADROOM_DB if is_engine_bed else 0.0)
    # F40: perceived loudness is not linear in decibels. The original
    # 20*log10(throttle) was practically inaudible at low throttle on speakers.
    # 0.70 retains contrast and makes partial thrust clearly audible.
    var linear_level_db: float = linear_to_db(maxf(level, 0.035))
    var target: float = audible_peak + 0.70 * linear_level_db \
        if level > 0.015 else (-80.0 if is_engine_bed else -53.0)
    # F41: never stop engine beds merely because the throttle crossed zero
    # momentarily. Keeping their PCM streams alive prevents clicks, reimports
    # and missed restarts during fast W/A/S/D input. RCS loops remain transient.
    if not player.playing and (level > 0.015 or is_engine_bed):
        player.volume_db = -80.0 if is_engine_bed else -46.0
        player.play()
        if is_engine_bed and level > 0.015:
            _engine_watchdog_restarts += 1
            push_warning("F41 AUDIO: restored %s at %.0f%% throttle (previous RCS: %s)" % [
                player.name, level * 100.0, _last_rcs_event_detail])
    var rate: float = 140.0 if level > 0.015 else 85.0
    player.volume_db = move_toward(player.volume_db, target, delta * rate)
    if not is_engine_bed and level <= 0.015 and player.volume_db <= -50.0 and player.playing:
        player.stop()


func _restore_engine_voice(player: AudioStreamPlayer, throttle: float,
        peak_db: float) -> void:
    if player == null or player.stream == null or player.playing:
        return
    # Independent watchdog: RCS and impact one-shots cannot hold the motor off.
    var gain: float = maxf(_master_level * _engine_level, 0.001)
    player.volume_db = peak_db - ENGINE_HEADROOM_DB + linear_to_db(gain) \
        + 0.70 * linear_to_db(maxf(throttle, 0.035))
    player.play()
    _engine_watchdog_restarts += 1
    push_warning("F41 AUDIO: restarted loop %s (engine %.0f%%, RCS %s)" % [
        player.name, throttle * 100.0, _last_rcs_event_detail])


func _check_engine_transport(player: AudioStreamPlayer, throttle: float,
        peak_db: float, delta: float) -> void:
    if player == null or player.stream == null:
        return
    # `playing` alone is insufficient: an imported sample with an invalid
    # loop boundary can reach the end and leave a stale/silent voice.
    # An unexpected pause can likewise keep `playing` true at 100% thrust.
    if player.stream_paused:
        player.stream_paused = false
        _engine_unpause_recoveries += 1
    var key: String = player.name
    var current: float = player.get_playback_position()
    var previous: float = float(_engine_transport_positions.get(key, -1.0))
    _engine_transport_positions[key] = current
    if previous < 0.0 or absf(current - previous) > 0.001:
        _engine_transport_stalls[key] = 0.0
        return
    var stalled: float = float(_engine_transport_stalls.get(key, 0.0)) + delta
    if stalled < 0.70:
        _engine_transport_stalls[key] = stalled
        return
    # Voice still reports `playing`, but its sample clock has frozen. Reopen
    # that voice without touching the other engine layer or the steering RCS.
    player.stop()
    var gain: float = maxf(_master_level * _engine_level, 0.001)
    player.volume_db = peak_db - ENGINE_HEADROOM_DB + linear_to_db(gain) + \
        0.70 * linear_to_db(maxf(throttle, 0.035))
    player.play()
    _engine_transport_stalls[key] = 0.0
    _engine_transport_positions[key] = -1.0
    _engine_stall_recoveries += 1
    push_warning("F42 AUDIO: stalled engine voice, restarted %s (%.0f%%)" % [
        key, throttle * 100.0])


func diagnostic_status() -> String:
    if DisplayServer.get_name() == "headless":
        return "Audio disabled: headless mode (no audio output)"
    var loaded: int = 0
    for player in _all_players():
        if player != null and player.stream != null:
            loaded += 1
    var mixer: String = "MUTED (M)" if _mix_muted else "active"
    if _master_level < 0.001:
        mixer = "MUTED (master volume 0)"
    if _audio_test_step >= 0:
        mixer = "INDEPENDENT TEST (bypasses mute and sliders)"
    var output_name: String = AudioServer.output_device
    var bus_state: String = "MUTE" if AudioServer.is_bus_mute(0) else "active"
    var engine_source: String = str(_loaded_audio_paths.get("MainEngineAudio", ""))
    var engine_state: String = "no WAV" if engine == null or engine.stream == null else (
        "playing" if engine.playing else "stopped")
    var turbine_state: String = "no WAV" if engine_turbine == null or engine_turbine.stream == null else (
        "playing" if engine_turbine.playing else "stopped")
    var rcs_state: String = "playing" if rcs != null and rcs.playing else "stopped"
    var engine_db: float = engine.volume_db if engine != null else -80.0
    var engine_pos: float = engine.get_playback_position() if engine != null and engine.playing else -1.0
    var engine_pcm: AudioStreamWAV = engine.stream as AudioStreamWAV if engine != null else null
    var engine_loop: String = "no WAV" if engine_pcm == null else (
        "FORWARD" if engine_pcm.loop_mode == AudioStreamWAV.LOOP_FORWARD else "NO LOOP")
    var finished: bool = episode.is_finished()
    var flight_state: String = episode.result_name()
    if finished:
        flight_state += " (FINAL: %s; press R to reset)" % episode.end_reason
    return "%d/11 WAV | Driver: %s | Output: %s\nBus: %s | Mix: %s | Flight: %s\nEngine: %.0f%% (command %.0f%%) | channel %.0f%%\nLoop: %s / %.1f dB | format: %s | position: %.2f s\nTurbine: %s | RCS: %s | restarts: %d\nRecoveries: stalls %d / pauses %d\nPrevious WASD: %s\nSource: %s\n%s" % [
        loaded, AudioServer.get_driver_name(), output_name, bus_state, mixer,
        flight_state, _live_throttle * 100.0, rocket.throttle * 100.0, _engine_level * 100.0,
        engine_state, engine_db, engine_loop, engine_pos, turbine_state, rcs_state,
        _engine_watchdog_restarts, _engine_stall_recoveries, _engine_unpause_recoveries,
        _last_rcs_event_detail, engine_source, _audio_test_note]


func start_audio_test() -> bool:
    if DisplayServer.get_name() == "headless":
        return false
    if engine == null or engine_ignition == null or engine_turbine == null or rcs_hiss == null or landing_confirm == null \
            or engine.stream == null or engine_ignition.stream == null or engine_turbine.stream == null \
            or rcs_hiss.stream == null or landing_confirm.stream == null:
        _audio_test_note = "ERROR: missing WAV files. Reimport assets/audio/"
        push_warning("F25.2 AUDIO: cannot start test; WAV files are missing")
        return false
    if audio_test_player == null:
        return false
    audio_test_player.stop()
    _audio_test_step = 0
    _audio_test_remaining = 0.0
    _advance_audio_test(0.0)
    return true


func _advance_audio_test(delta: float) -> void:
    _audio_test_remaining -= delta
    if _audio_test_remaining > 0.0:
        return
    # During diagnosis we deliberately bypass saved mute/zero channels. Thus
    # a silent audition isolates an output device/driver/OS issue, rather
    # than the rocket control inputs or the F09 preference file.
    match _audio_test_step:
        0:
            _play_audio_test_sample(engine_ignition, -4.0)
            _audio_test_note = "1/5: engine ignition"
            _audio_test_remaining = 1.6
        1:
            _play_audio_test_sample(engine, -2.0)
            _audio_test_note = "2/5: ENGINE LOOP (3 s)"
            _audio_test_remaining = 3.0
        2:
            _play_audio_test_sample(engine_turbine, -5.0)
            _audio_test_note = "3/5: engine turbine (2 s)"
            _audio_test_remaining = 2.0
        3:
            _play_audio_test_sample(rcs_hiss, -4.0)
            _audio_test_note = "4/5: RCS gas (2 s)"
            _audio_test_remaining = 2.0
        4:
            _play_audio_test_sample(landing_confirm, -4.0)
            _audio_test_note = "5/5: touchdown"
            _audio_test_remaining = 1.3
        _:
            audio_test_player.stop()
            _audio_test_step = -1
            _audio_test_note = "Test complete. If inaudible, check Windows audio output."
            print("F25.2 AUDIO: test sequence complete, driver=" +
                AudioServer.get_driver_name())
            return
    _audio_test_step += 1


func _play_audio_test_sample(player: AudioStreamPlayer, level_db: float) -> void:
    audio_test_player.stop()
    audio_test_player.stream = player.stream
    audio_test_player.pitch_scale = 1.0
    audio_test_player.volume_db = level_db
    audio_test_player.play()
    print("F25.2 AUDIO: test %s, playing=%s, driver=%s" % [
        player.name, str(audio_test_player.playing), AudioServer.get_driver_name()])
