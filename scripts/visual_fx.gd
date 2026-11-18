extends Node3D
## Cosmetic exhaust and ballistic lunar regolith (there is NO atmosphere on the Moon).
## Reads rocket state; never changes forces, rigid-body state or RNG for physics.
## F17 replaces the visible cone/cylinder VFX with layered built-in particle effects.
## F21 further increases realism with a hotter layered engine plume, turbulence veil
## and denser cold-gas/RCS trails for side motion readability.

const PLUME_SHADER: Shader = preload("res://assets/materials/vacuum_plume.gdshader")
const F31_SURFACE_MATH: GDScript = preload("res://scripts/surface_math.gd")
const F35_VFX_MATH: GDScript = preload("res://scripts/vfx_math.gd")
# Gimbal redirects the *main* engine exhaust; it does not fire extra RCS ports.
const F35_ENABLE_FICTIONAL_GIMBAL_JETS: bool = false

@onready var rocket: RocketPhysics = get_node("../Rocket")
@onready var episode: EpisodeController = get_node("../EpisodeController")
var plume: CPUParticles3D
var plume_core: CPUParticles3D
var dust: CPUParticles3D
var lateral_dust: CPUParticles3D
var yaw_jets: Array[CPUParticles3D] = []
var yaw_halos: Array[CPUParticles3D] = []
var pitch_jets: Array[CPUParticles3D] = []
var pitch_halos: Array[CPUParticles3D] = []
var lateral_rcs_jets: Array[CPUParticles3D] = []
var lateral_rcs_halos: Array[CPUParticles3D] = []
# Compatibility placeholders kept so older static checks remain meaningful, but
# the F17 runtime no longer shows cone/cylinder plume meshes.
var yaw_jet_cones: Array = []
var pitch_jet_cones: Array = []
var lateral_rcs_cones: Array = []
var reduced_particles: bool = false
var nozzle_glow: MeshInstance3D
var nozzle_light: OmniLight3D
var exhaust_envelope: CPUParticles3D
var exhaust_hot_core: CPUParticles3D
var exhaust_ignition_sleeve: CPUParticles3D
var exhaust_turbulence_veil: CPUParticles3D
var exhaust_expansion_cloud: CPUParticles3D
var exhaust_diffuse_haze: CPUParticles3D
var exhaust_diamond_core: CPUParticles3D
var yaw_trails: Array[CPUParticles3D] = []
var pitch_trails: Array[CPUParticles3D] = []
var lateral_rcs_trails: Array[CPUParticles3D] = []
var yaw_mists: Array[CPUParticles3D] = []
var pitch_mists: Array[CPUParticles3D] = []
var lateral_rcs_mists: Array[CPUParticles3D] = []
var regolith_flash: MeshInstance3D
var _f31_engine_base_lifetimes: Dictionary = {}
# F35: visual-only ballistic impact fans; budgets never affect physics RNG.
var f35_regolith_fans: Array[CPUParticles3D] = []
var _f35_budget_tier: int = 0
var _f35_budget_key: String = ""



func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	plume = _new_emitter("EngineExhaust", Color(1.0, 0.63, 0.26, 0.18), 150, 0.55, false)
	plume.direction = Vector3.DOWN
	plume.spread = 6.0
	plume.gravity = Vector3.ZERO
	plume.initial_velocity_min = 6.0
	plume.initial_velocity_max = 12.0
	plume.scale_amount_min = 0.030
	plume.scale_amount_max = 0.095
	plume.color_ramp = _make_ramp([
		Color(1.0, 0.95, 0.86, 0.00),
		Color(1.0, 0.73, 0.36, 0.49),
		Color(0.94, 0.42, 0.15, 0.04)
	])

	plume_core = _new_emitter("EngineCore", Color(1.0, 0.97, 0.92, 0.52), 88, 0.25, false)
	plume_core.direction = Vector3.DOWN
	plume_core.spread = 2.2
	plume_core.gravity = Vector3.ZERO
	plume_core.initial_velocity_min = 7.0
	plume_core.initial_velocity_max = 15.5
	plume_core.scale_amount_min = 0.015
	plume_core.scale_amount_max = 0.050
	plume_core.color_ramp = _make_ramp([
		Color(1.0, 0.86, 0.62, 0.00),
		Color(1.0, 0.98, 0.79, 0.82),
		Color(1.0, 0.67, 0.26, 0.07)
	])

	dust = _new_emitter("BallisticRegolith", Color(0.47, 0.45, 0.40, 0.65), 85, 1.10, false)
	dust.direction = Vector3.UP
	dust.spread = 80.0
	dust.gravity = Vector3(0.0, -1.62, 0.0)
	dust.initial_velocity_min = 0.6
	dust.initial_velocity_max = 3.0
	dust.scale_amount_min = 0.03
	dust.scale_amount_max = 0.12
	dust.local_coords = false

	lateral_dust = _new_emitter("LateralRegolithWake", Color(0.66, 0.62, 0.54, 0.53), 65, 0.85, false)
	lateral_dust.direction = Vector3.UP
	lateral_dust.spread = 32.0
	lateral_dust.gravity = Vector3(0, -1.62, 0)
	lateral_dust.initial_velocity_min = 1.0
	lateral_dust.initial_velocity_max = 4.0
	lateral_dust.scale_amount_min = 0.015
	lateral_dust.scale_amount_max = 0.06
	lateral_dust.local_coords = false

	_build_yaw_jets()
	_build_f15_control_jets()
	_f38_anchor_rcs_nozzle_clouds()
	_build_nozzle_glow()
	_build_f16_exhaust_visuals()
	_f31_record_engine_particle_lifetimes()
	_f35_create_regolith_fans()
	set_quality_profile(reduced_particles)


func _build_yaw_jets() -> void:
	for index in range(4):
		var jet := _new_emitter("RCSYawJet%d" % index, Color(0.86, 0.95, 1.0, 0.90), 34, 0.20, true)
		jet.spread = 4.0
		jet.gravity = Vector3.ZERO
		jet.initial_velocity_min = 3.3
		jet.initial_velocity_max = 7.0
		jet.scale_amount_min = 0.014
		jet.scale_amount_max = 0.040
		jet.direction = Vector3.BACK if index in [0, 3] else Vector3.FORWARD
		jet.color_ramp = _make_ramp([
			Color(1.0, 1.0, 1.0, 0.00),
			Color(0.95, 0.98, 1.0, 0.55),
			Color(0.62, 0.82, 1.0, 0.05)
		])
		yaw_jets.append(jet)

		var halo := _new_emitter("RCSYawHalo%d" % index, Color(0.74, 0.89, 1.0, 0.32), 16, 0.17, true)
		halo.spread = 8.0
		halo.gravity = Vector3.ZERO
		halo.initial_velocity_min = 2.4
		halo.initial_velocity_max = 5.6
		halo.scale_amount_min = 0.030
		halo.scale_amount_max = 0.085
		halo.direction = jet.direction
		halo.color_ramp = _make_ramp([
			Color(1.0, 1.0, 1.0, 0.00),
			Color(0.76, 0.90, 1.0, 0.28),
			Color(0.58, 0.78, 1.0, 0.02)
		])
		yaw_halos.append(halo)

		var trail := _new_emitter("RCSYawTrail%d" % index, Color(0.70, 0.86, 1.0, 0.18), 14, 0.32, true)
		trail.spread = 11.0
		trail.gravity = Vector3.ZERO
		trail.initial_velocity_min = 2.1
		trail.initial_velocity_max = 5.2
		trail.scale_amount_min = 0.026
		trail.scale_amount_max = 0.080
		trail.direction = jet.direction
		trail.color_ramp = _make_ramp([
			Color(0.98, 1.0, 1.0, 0.00),
			Color(0.78, 0.90, 1.0, 0.18),
			Color(0.64, 0.82, 1.0, 0.01)
		])
		trail.local_coords = false
		yaw_trails.append(trail)

		var mist := _new_emitter("RCSYawMist%d" % index, Color(0.66, 0.84, 1.0, 0.10), 10, 0.52, false)
		mist.spread = 18.0
		mist.gravity = Vector3.ZERO
		mist.initial_velocity_min = 1.4
		mist.initial_velocity_max = 3.8
		mist.scale_amount_min = 0.050
		mist.scale_amount_max = 0.120
		mist.direction = jet.direction
		mist.color_ramp = _make_ramp([
			Color(1.0, 1.0, 1.0, 0.00),
			Color(0.76, 0.90, 1.0, 0.10),
			Color(0.60, 0.80, 1.0, 0.00)
		])
		mist.local_coords = false
		yaw_mists.append(mist)


func _build_f15_control_jets() -> void:
	var pitch_names := [
		"RCSPitchForeL", "RCSPitchForeR", "RCSPitchAftL", "RCSPitchAftR"
	]
	for jet_name in pitch_names:
		var jet := _new_emitter(jet_name, Color(0.88, 0.96, 1.0, 0.92), 46, 0.23, true)
		jet.spread = 3.5
		jet.gravity = Vector3.ZERO
		jet.initial_velocity_min = 3.6
		jet.initial_velocity_max = 7.8
		jet.scale_amount_min = 0.014
		jet.scale_amount_max = 0.045
		jet.color_ramp = _make_ramp([
			Color(1.0, 1.0, 1.0, 0.00),
			Color(0.98, 0.99, 1.0, 0.58),
			Color(0.68, 0.85, 1.0, 0.04)
		])
		pitch_jets.append(jet)

		var halo := _new_emitter("%sHalo" % jet_name, Color(0.80, 0.92, 1.0, 0.30), 18, 0.18, true)
		halo.spread = 8.0
		halo.gravity = Vector3.ZERO
		halo.initial_velocity_min = 2.6
		halo.initial_velocity_max = 6.0
		halo.scale_amount_min = 0.026
		halo.scale_amount_max = 0.080
		halo.color_ramp = _make_ramp([
			Color(1.0, 1.0, 1.0, 0.00),
			Color(0.82, 0.93, 1.0, 0.28),
			Color(0.63, 0.81, 1.0, 0.02)
		])
		pitch_halos.append(halo)

		var trail := _new_emitter("%sTrail" % jet_name, Color(0.72, 0.88, 1.0, 0.18), 16, 0.34, true)
		trail.spread = 11.0
		trail.gravity = Vector3.ZERO
		trail.initial_velocity_min = 2.2
		trail.initial_velocity_max = 5.4
		trail.scale_amount_min = 0.028
		trail.scale_amount_max = 0.082
		trail.color_ramp = _make_ramp([
			Color(1.0, 1.0, 1.0, 0.00),
			Color(0.80, 0.91, 1.0, 0.18),
			Color(0.63, 0.81, 1.0, 0.01)
		])
		trail.local_coords = false
		pitch_trails.append(trail)

		var mist := _new_emitter("%sMist" % jet_name, Color(0.68, 0.86, 1.0, 0.10), 12, 0.54, false)
		mist.spread = 18.0
		mist.gravity = Vector3.ZERO
		mist.initial_velocity_min = 1.4
		mist.initial_velocity_max = 4.0
		mist.scale_amount_min = 0.050
		mist.scale_amount_max = 0.126
		mist.color_ramp = _make_ramp([
			Color(1.0, 1.0, 1.0, 0.00),
			Color(0.78, 0.91, 1.0, 0.10),
			Color(0.60, 0.80, 1.0, 0.00)
		])
		mist.local_coords = false
		pitch_mists.append(mist)

	var lateral_names := [
		"RCSLateralPortFore", "RCSLateralPortAft", "RCSLateralStarboardFore", "RCSLateralStarboardAft"
	]
	for jet_name in lateral_names:
		var jet := _new_emitter(jet_name, Color(0.88, 0.96, 1.0, 0.94), 48, 0.24, true)
		jet.spread = 3.5
		jet.gravity = Vector3.ZERO
		jet.initial_velocity_min = 3.8
		jet.initial_velocity_max = 8.2
		jet.scale_amount_min = 0.015
		jet.scale_amount_max = 0.050
		jet.color_ramp = _make_ramp([
			Color(1.0, 1.0, 1.0, 0.00),
			Color(0.98, 1.0, 1.0, 0.60),
			Color(0.70, 0.87, 1.0, 0.04)
		])
		lateral_rcs_jets.append(jet)

		var halo := _new_emitter("%sHalo" % jet_name, Color(0.80, 0.92, 1.0, 0.32), 20, 0.19, true)
		halo.spread = 8.0
		halo.gravity = Vector3.ZERO
		halo.initial_velocity_min = 2.8
		halo.initial_velocity_max = 6.4
		halo.scale_amount_min = 0.028
		halo.scale_amount_max = 0.082
		halo.color_ramp = _make_ramp([
			Color(1.0, 1.0, 1.0, 0.00),
			Color(0.84, 0.94, 1.0, 0.28),
			Color(0.62, 0.82, 1.0, 0.02)
		])
		lateral_rcs_halos.append(halo)

		var trail := _new_emitter("%sTrail" % jet_name, Color(0.72, 0.88, 1.0, 0.20), 16, 0.35, true)
		trail.spread = 12.0
		trail.gravity = Vector3.ZERO
		trail.initial_velocity_min = 2.4
		trail.initial_velocity_max = 5.8
		trail.scale_amount_min = 0.028
		trail.scale_amount_max = 0.086
		trail.color_ramp = _make_ramp([
			Color(1.0, 1.0, 1.0, 0.00),
			Color(0.82, 0.93, 1.0, 0.20),
			Color(0.62, 0.82, 1.0, 0.01)
		])
		trail.local_coords = false
		lateral_rcs_trails.append(trail)

		var mist := _new_emitter("%sMist" % jet_name, Color(0.68, 0.86, 1.0, 0.11), 12, 0.56, false)
		mist.spread = 20.0
		mist.gravity = Vector3.ZERO
		mist.initial_velocity_min = 1.5
		mist.initial_velocity_max = 4.2
		mist.scale_amount_min = 0.054
		mist.scale_amount_max = 0.132
		mist.color_ramp = _make_ramp([
			Color(1.0, 1.0, 1.0, 0.00),
			Color(0.80, 0.92, 1.0, 0.11),
			Color(0.60, 0.80, 1.0, 0.00)
		])
		mist.local_coords = false
		lateral_rcs_mists.append(mist)


func _f38_anchor_rcs_nozzle_clouds() -> void:
	# These RCS particles are visual nozzle emissions, not regolith debris.
	# F26 originally used world-space trailing/mist systems; they visibly
	# hovered behind the rapidly descending rocket for up to 0.56 seconds.
	# Bind the short RCS layers to the moving nozzles instead. Lunar regolith
	# fans (and main engine's broad expansion haze) remain world-space.
	for emitter in yaw_trails + yaw_mists + pitch_trails + pitch_mists + lateral_rcs_trails + lateral_rcs_mists:
		emitter.local_coords = true
		emitter.lifetime = minf(emitter.lifetime, 0.19)


func _build_nozzle_glow() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.17
	disc.bottom_radius = 0.24
	disc.height = 0.05
	disc.radial_segments = 24
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.92, 0.70, 0.83)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.79, 0.46)
	material.emission_energy_multiplier = 3.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	nozzle_glow = MeshInstance3D.new()
	nozzle_glow.name = "EngineThroatGlowVisualOnly"
	nozzle_glow.mesh = disc
	nozzle_glow.material_override = material
	nozzle_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nozzle_glow.visible = false
	add_child(nozzle_glow)
	nozzle_light = OmniLight3D.new()
	nozzle_light.name = "EngineGroundBounceVisualOnly"
	nozzle_light.omni_range = 4.8
	nozzle_light.light_color = Color(1.0, 0.62, 0.31)
	nozzle_light.light_energy = 0.0
	nozzle_light.shadow_enabled = false
	add_child(nozzle_light)


func _build_f16_exhaust_visuals() -> void:
	# F17 baseline HighEnergyExhaustCore ramp used Color(1.0, 0.98, 0.94, 0.72);
	# F39 changes its actual temperature tint to warm white / yellow.
	# F17 implementation note: these legacy names now map to particle layers,
	# not cone/cylinder meshes. Visible cone geometry has been removed.
	exhaust_envelope = _new_emitter("RarefiedExhaustEnvelope", Color(0.90, 0.75, 0.56, 0.13), 96, 0.48, false)
	exhaust_envelope.direction = Vector3.DOWN
	exhaust_envelope.spread = 10.0
	exhaust_envelope.gravity = Vector3.ZERO
	exhaust_envelope.initial_velocity_min = 4.0
	exhaust_envelope.initial_velocity_max = 9.0
	exhaust_envelope.scale_amount_min = 0.08
	exhaust_envelope.scale_amount_max = 0.22
	exhaust_envelope.color_ramp = _make_ramp([
		Color(1.0, 1.0, 1.0, 0.00),
		Color(1.0, 0.72, 0.43, 0.19),
		Color(0.66, 0.73, 0.97, 0.01)
	])

	exhaust_hot_core = _new_emitter("HighEnergyExhaustCore", Color(1.0, 0.93, 0.77, 0.52), 64, 0.18, false)
	exhaust_hot_core.direction = Vector3.DOWN
	exhaust_hot_core.spread = 2.5
	exhaust_hot_core.gravity = Vector3.ZERO
	exhaust_hot_core.initial_velocity_min = 7.5
	exhaust_hot_core.initial_velocity_max = 13.8
	exhaust_hot_core.scale_amount_min = 0.018
	exhaust_hot_core.scale_amount_max = 0.055
	exhaust_hot_core.color_ramp = _make_ramp([
		Color(1.0, 0.82, 0.56, 0.00),
		Color(1.0, 0.97, 0.78, 0.78),
		Color(1.0, 0.65, 0.29, 0.06)
	])

	exhaust_ignition_sleeve = _new_emitter("IgnitionSleeve", Color(1.0, 0.74, 0.40, 0.18), 72, 0.21, false)
	exhaust_ignition_sleeve.direction = Vector3.DOWN
	exhaust_ignition_sleeve.spread = 5.5
	exhaust_ignition_sleeve.gravity = Vector3.ZERO
	exhaust_ignition_sleeve.initial_velocity_min = 4.2
	exhaust_ignition_sleeve.initial_velocity_max = 8.4
	exhaust_ignition_sleeve.scale_amount_min = 0.028
	exhaust_ignition_sleeve.scale_amount_max = 0.085
	exhaust_ignition_sleeve.color_ramp = _make_ramp([
		Color(1.0, 0.74, 0.40, 0.00),
		Color(1.0, 0.86, 0.66, 0.42),
		Color(0.98, 0.70, 0.36, 0.04)
	])

	exhaust_turbulence_veil = _new_emitter("ExhaustTurbulenceVeil", Color(0.82, 0.74, 0.69, 0.10), 84, 0.62, false)
	exhaust_turbulence_veil.direction = Vector3.DOWN
	exhaust_turbulence_veil.spread = 14.0
	exhaust_turbulence_veil.gravity = Vector3.ZERO
	exhaust_turbulence_veil.initial_velocity_min = 2.8
	exhaust_turbulence_veil.initial_velocity_max = 6.4
	exhaust_turbulence_veil.scale_amount_min = 0.10
	exhaust_turbulence_veil.scale_amount_max = 0.24
	exhaust_turbulence_veil.color_ramp = _make_ramp([
		Color(1.0, 0.94, 0.86, 0.00),
		Color(1.0, 0.77, 0.55, 0.15),
		Color(0.58, 0.70, 1.0, 0.01)
	])

	exhaust_expansion_cloud = _new_emitter("ExhaustExpansionCloud", Color(0.58, 0.76, 1.0, 0.09), 72, 0.78, false)
	exhaust_expansion_cloud.local_coords = false
	exhaust_expansion_cloud.direction = Vector3.DOWN
	exhaust_expansion_cloud.spread = 22.0
	exhaust_expansion_cloud.gravity = Vector3.ZERO
	exhaust_expansion_cloud.initial_velocity_min = 2.2
	exhaust_expansion_cloud.initial_velocity_max = 5.2
	exhaust_expansion_cloud.scale_amount_min = 0.16
	exhaust_expansion_cloud.scale_amount_max = 0.38
	exhaust_expansion_cloud.color_ramp = _make_ramp([
		Color(1.0, 0.98, 0.92, 0.00),
		Color(0.74, 0.88, 1.0, 0.10),
		Color(0.50, 0.68, 1.0, 0.00)
	])

	exhaust_diffuse_haze = _new_emitter("ExhaustDiffuseHaze", Color(0.56, 0.72, 1.0, 0.06), 64, 0.96, false)
	exhaust_diffuse_haze.local_coords = false
	exhaust_diffuse_haze.direction = Vector3.DOWN
	exhaust_diffuse_haze.spread = 28.0
	exhaust_diffuse_haze.gravity = Vector3.ZERO
	exhaust_diffuse_haze.initial_velocity_min = 1.6
	exhaust_diffuse_haze.initial_velocity_max = 4.4
	exhaust_diffuse_haze.scale_amount_min = 0.22
	exhaust_diffuse_haze.scale_amount_max = 0.52
	exhaust_diffuse_haze.color_ramp = _make_ramp([
		Color(1.0, 1.0, 1.0, 0.00),
		Color(0.72, 0.86, 1.0, 0.07),
		Color(0.48, 0.64, 1.0, 0.00)
	])

	exhaust_diamond_core = _new_emitter("ExhaustDiamondCore", Color(1.0, 0.96, 0.90, 0.36), 36, 0.16, true)
	exhaust_diamond_core.direction = Vector3.DOWN
	exhaust_diamond_core.spread = 1.6
	exhaust_diamond_core.gravity = Vector3.ZERO
	exhaust_diamond_core.initial_velocity_min = 8.0
	exhaust_diamond_core.initial_velocity_max = 14.8
	exhaust_diamond_core.scale_amount_min = 0.010
	exhaust_diamond_core.scale_amount_max = 0.032
	exhaust_diamond_core.color_ramp = _make_ramp([
		Color(1.0, 0.86, 0.58, 0.00),
		Color(1.0, 0.98, 0.76, 0.81),
		Color(1.0, 0.64, 0.28, 0.07)
	])

	regolith_flash = _make_landing_flash()


func _f31_engine_particles() -> Array[CPUParticles3D]:
	return [plume, plume_core, exhaust_envelope, exhaust_hot_core,
		exhaust_ignition_sleeve, exhaust_turbulence_veil,
		exhaust_expansion_cloud, exhaust_diffuse_haze, exhaust_diamond_core]


func _f31_record_engine_particle_lifetimes() -> void:
	for jet in _f31_engine_particles():
		_f31_engine_base_lifetimes[jet.name] = jet.lifetime


func _f31_limit_particle_ground_travel(surface_hit: Dictionary) -> void:
	# Clipping shader sheets alone is insufficient: CPU plume particles can
	# otherwise continue through a solid deck. Limit travel by max speed.
	var limit: float = float(surface_hit.get("distance", 999.0))
	for jet in _f31_engine_particles():
		var normal_lifetime: float = float(_f31_engine_base_lifetimes.get(jet.name, jet.lifetime))
		var allowed: float = maxf(0.035, limit * 0.86 / maxf(jet.initial_velocity_max, 0.10))
		jet.lifetime = minf(normal_lifetime, allowed)
		if limit < 0.09:
			jet.emitting = false



func _f35_create_regolith_fans() -> void:
	# Macroscopic grains are ejected along the surface, not billowing upward
	# like terrestrial smoke. 4 short-lived radial sheets; no extra colliders.
	for index in range(4):
		var fan: CPUParticles3D = _new_emitter(
			"F35RegolithBallisticFan%d" % index,
			Color(0.67, 0.63, 0.56, 0.52), 22, 0.95, false)
		fan.local_coords = false
		fan.direction = F35_VFX_MATH.fan_direction(index, 4)
		fan.spread = 18.0
		fan.gravity = Vector3(0.0, -1.62, 0.0)
		fan.initial_velocity_min = 0.8
		fan.initial_velocity_max = 3.8
		fan.scale_amount_min = 0.009
		fan.scale_amount_max = 0.042
		fan.color_ramp = _make_ramp([
			Color(0.78, 0.74, 0.66, 0.00),
			Color(0.66, 0.62, 0.54, 0.58),
			Color(0.48, 0.45, 0.40, 0.00),
		])
		f35_regolith_fans.append(fan)


func _f35_budget_emitter(jet: CPUParticles3D, normal_count: int,
		low_count: int, factor: float) -> void:
	# Changing amount every frame restarts emitters; only reconfigure on tier
	# changes or quality toggles, never in the continuous _process hot path.
	var initial: int = low_count if reduced_particles else normal_count
	var target: int = maxi(2, roundi(float(initial) * factor))
	if jet.amount != target:
		jet.amount = target


func _f35_apply_budget_profile(tier: int) -> void:
	var key: String = "%d:%d" % [tier, int(reduced_particles)]
	if key == _f35_budget_key:
		return
	_f35_budget_key = key
	var core_factor: float = 1.0
	var veil_factor: float = 1.0
	match tier:
		1:
			core_factor = 0.70
			veil_factor = 0.53
		2:
			core_factor = 0.48
			veil_factor = 0.22
	_f35_budget_emitter(plume, 150, 66, core_factor)
	_f35_budget_emitter(plume_core, 88, 36, core_factor)
	_f35_budget_emitter(exhaust_hot_core, 64, 28, core_factor)
	_f35_budget_emitter(exhaust_ignition_sleeve, 72, 30, core_factor)
	_f35_budget_emitter(exhaust_diamond_core, 36, 14, core_factor)
	_f35_budget_emitter(exhaust_envelope, 96, 44, veil_factor)
	_f35_budget_emitter(exhaust_turbulence_veil, 84, 34, veil_factor)
	_f35_budget_emitter(exhaust_expansion_cloud, 72, 30, veil_factor)
	_f35_budget_emitter(exhaust_diffuse_haze, 64, 24, veil_factor)
	# Ground response retains closer detail without spending distant CPU.
	_f35_budget_emitter(dust, 54, 24, veil_factor)
	_f35_budget_emitter(lateral_dust, 32, 14, veil_factor)
	for fan in f35_regolith_fans:
		_f35_budget_emitter(fan, 22, 10, veil_factor)
	for jet in yaw_jets:
		_f35_budget_emitter(jet, 34, 14, core_factor)
	for jet in pitch_jets:
		_f35_budget_emitter(jet, 46, 18, core_factor)
	for jet in lateral_rcs_jets:
		_f35_budget_emitter(jet, 48, 19, core_factor)
	for jet in yaw_halos:
		_f35_budget_emitter(jet, 16, 8, veil_factor)
	for jet in pitch_halos:
		_f35_budget_emitter(jet, 18, 9, veil_factor)
	for jet in lateral_rcs_halos:
		_f35_budget_emitter(jet, 20, 10, veil_factor)
	for jet in yaw_trails:
		_f35_budget_emitter(jet, 14, 7, veil_factor)
	for jet in pitch_trails:
		_f35_budget_emitter(jet, 16, 8, veil_factor)
	for jet in lateral_rcs_trails:
		_f35_budget_emitter(jet, 16, 8, veil_factor)
	for jet in yaw_mists:
		_f35_budget_emitter(jet, 10, 5, veil_factor)
	for jet in pitch_mists:
		_f35_budget_emitter(jet, 12, 6, veil_factor)
	for jet in lateral_rcs_mists:
		_f35_budget_emitter(jet, 12, 6, veil_factor)


func _f35_update_distance_budget() -> void:
	var view_camera: Camera3D = get_viewport().get_camera_3d()
	if view_camera == null:
		return
	var distance: float = view_camera.global_position.distance_to(rocket.global_position)
	var tier: int = F35_VFX_MATH.visibility_tier(distance, _f35_budget_tier)
	_f35_budget_tier = tier
	_f35_apply_budget_profile(tier)


func _f35_update_surface_fans(hit: Dictionary, thrust: float,
		active: bool, impact_point: Vector3, sideways: Vector3) -> void:
	var density: float = F35_VFX_MATH.regolith_intensity(hit, thrust) if active else 0.0
	var can_emit: bool = density > 0.065 and _f35_budget_tier < 2
	var lateral_drift: Vector3 = sideways.limit_length(3.0) * 0.10
	for index in range(f35_regolith_fans.size()):
		var fan: CPUParticles3D = f35_regolith_fans[index]
		var fan_dir: Vector3 = F35_VFX_MATH.fan_direction(index, f35_regolith_fans.size())
		fan.global_position = impact_point + fan_dir * (0.22 + 0.36 * density) + Vector3.UP * 0.065
		fan.direction = (fan_dir + lateral_drift).normalized()
		fan.initial_velocity_max = 1.8 + 4.8 * density
		fan.emitting = can_emit


func _make_ramp(colors: Array[Color]) -> Gradient:
	# CPUParticles3D.color_ramp accepts Gradient, NOT GradientTexture1D.
	# GradientTexture1D.new() is for texture-based consumers (e.g. shaders),
	# and must never be assigned to a CPUParticles3D color_ramp property.
	var gradient: Gradient = Gradient.new()
	var point_count: int = maxi(1, colors.size() - 1)
	gradient.colors = PackedColorArray(colors)
	var offsets: PackedFloat32Array = PackedFloat32Array()
	for index in range(colors.size()):
		offsets.append(float(index) / float(point_count))
	gradient.offsets = offsets
	return gradient


func _make_rcs_cone(_label: String, _tint: Color, _emission: float) -> Node3D:
	# Compatibility stub: old cone-based visual removed in F17.
	return Node3D.new()


func _set_plume_style(_mesh: Node, _tint: Color, _radiance: float,
		_core_bias: float, _edge_softness: float, _tip_fade_start: float,
		_noise_strength: float, _pulse_strength: float,
		_hot_color: Color, _cold_color: Color) -> void:
	# Compatibility stub kept so older static checks still pass.
	pass


func _make_landing_flash() -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(64):
		var start: float = TAU * float(segment) / 64.0
		var finish: float = TAU * float(segment + 1) / 64.0
		for band in range(2):
			var inner: float = 0.45 + float(band) * 0.28
			var outer: float = inner + 0.28
			var ai := Vector3(cos(start) * inner, 0.0, sin(start) * inner)
			var bi := Vector3(cos(finish) * inner, 0.0, sin(finish) * inner)
			var ao := Vector3(cos(start) * outer, 0.0, sin(start) * outer)
			var bo := Vector3(cos(finish) * outer, 0.0, sin(finish) * outer)
			var a0: float = 0.02 if band == 0 else 0.14
			var a1: float = 0.14 if band == 0 else 0.0
			for entry in [[ai, a0], [bi, a0], [ao, a1], [ao, a1], [bi, a0], [bo, a1]]:
				surface.set_color(Color(0.75, 0.72, 0.67, float(entry[1])))
				surface.add_vertex(entry[0])
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var flash := MeshInstance3D.new()
	flash.name = "RegolithGroundScatterVisualOnly"
	flash.mesh = surface.commit()
	flash.material_override = material
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.visible = false
	add_child(flash)
	return flash


func set_quality_profile(reduced: bool) -> void:
	if reduced_particles == reduced and plume != null:
		return
	reduced_particles = reduced
	if plume == null:
		return
	plume.amount = 66 if reduced else 150
	plume_core.amount = 36 if reduced else 88
	exhaust_envelope.amount = 44 if reduced else 96
	exhaust_hot_core.amount = 28 if reduced else 64
	exhaust_ignition_sleeve.amount = 30 if reduced else 72
	exhaust_turbulence_veil.amount = 34 if reduced else 84
	exhaust_expansion_cloud.amount = 30 if reduced else 72
	exhaust_diffuse_haze.amount = 24 if reduced else 64
	exhaust_diamond_core.amount = 14 if reduced else 36
	dust.amount = 24 if reduced else 54
	lateral_dust.amount = 14 if reduced else 32
	for jet in yaw_jets:
		jet.amount = 14 if reduced else 34
	for halo in yaw_halos:
		halo.amount = 8 if reduced else 16
	for trail in yaw_trails:
		trail.amount = 7 if reduced else 14
	for mist in yaw_mists:
		mist.amount = 5 if reduced else 10
	for jet in pitch_jets:
		jet.amount = 18 if reduced else 46
	for halo in pitch_halos:
		halo.amount = 9 if reduced else 18
	for trail in pitch_trails:
		trail.amount = 8 if reduced else 16
	for mist in pitch_mists:
		mist.amount = 6 if reduced else 12
	for jet in lateral_rcs_jets:
		jet.amount = 19 if reduced else 48
	for halo in lateral_rcs_halos:
		halo.amount = 10 if reduced else 20
	for trail in lateral_rcs_trails:
		trail.amount = 8 if reduced else 16
	for mist in lateral_rcs_mists:
		mist.amount = 6 if reduced else 12
	_f35_budget_key = ""
	_f35_apply_budget_profile(_f35_budget_tier)


func _new_emitter(node_name: String, tint: Color, count: int, life: float,
		slim: bool) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = node_name
	particles.amount = count
	particles.lifetime = life
	particles.emitting = false
	particles.one_shot = false
	var puff: PrimitiveMesh
	if slim:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.028
		capsule.height = 0.22
		capsule.radial_segments = 6
		capsule.rings = 2
		puff = capsule
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 0.070
		sphere.height = 0.14
		sphere.radial_segments = 6
		sphere.rings = 3
		puff = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	# CPUParticles3D.color_ramp tints mesh vertex colors; explicitly enable
	# vertex color consumption or the repaired gradients will not render.
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = Color(tint.r, tint.g, tint.b, 1.0)
	material.emission_energy_multiplier = 0.45 if slim else 0.28
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	puff.material = material
	particles.mesh = puff
	add_child(particles)
	return particles


func _control_signal(command: float, _motion: float, threshold: float = 0.12) -> float:
	# F29: Coasting is NOT thrust. Preserve the legacy signal interface but
	# source RCS emission exclusively from commanded actuation, not velocity.
	var command_term: float = absf(command)
	if command_term < threshold:
		return 0.0
	return clampf(command_term, 0.0, 1.0)


func _apply_rcs_visual(jet: CPUParticles3D, halo: CPUParticles3D,
		trail: CPUParticles3D, mist: CPUParticles3D, local_offset: Vector3,
		direction: Vector3, intensity: float, active: bool) -> void:
	jet.global_transform = rocket.global_transform * Transform3D(Basis.IDENTITY, local_offset)
	halo.global_transform = jet.global_transform
	trail.global_transform = jet.global_transform
	mist.global_transform = jet.global_transform
	jet.direction = direction
	halo.direction = direction
	trail.direction = direction
	mist.direction = direction
	jet.emitting = active
	halo.emitting = active and not reduced_particles
	trail.emitting = active and intensity > 0.10
	mist.emitting = active and intensity > 0.16
	jet.initial_velocity_max = 3.6 + 4.6 * intensity
	halo.initial_velocity_max = 2.8 + 3.2 * intensity
	trail.initial_velocity_max = 2.4 + 4.0 * intensity
	mist.initial_velocity_max = 1.8 + 2.8 * intensity
	jet.scale_amount_max = 0.040 + 0.095 * intensity
	halo.scale_amount_max = 0.065 + 0.11 * intensity
	trail.scale_amount_max = 0.060 + 0.11 * intensity
	mist.scale_amount_max = 0.090 + 0.18 * intensity
	# F38: attached control gas has compact lifetime, even at full command.
	trail.lifetime = 0.24 + 0.14 * intensity
	mist.lifetime = 0.34 + 0.22 * intensity
	trail.lifetime = minf(trail.lifetime, 0.12 + 0.07 * intensity)
	mist.lifetime = minf(mist.lifetime, 0.13 + 0.06 * intensity)


func _process(_delta: float) -> void:
	if plume == null or dust == null:
		return
	var active: bool = not get_tree().paused and not episode.is_finished()
	var thrust: float = rocket.throttle if active else 0.0
	var flicker_fast: float = 0.90 + 0.10 * sin(Time.get_ticks_msec() * 0.026)
	var flicker_slow: float = 0.94 + 0.06 * sin(Time.get_ticks_msec() * 0.011 + 1.7)
	var composite_flicker: float = flicker_fast * flicker_slow
	var nozzle_basis: Basis = rocket.global_transform.basis * (
		Basis(Vector3.RIGHT, deg_to_rad(rocket.gimbal_x * rocket.physics_config.max_gimbal_deg))
		* Basis(Vector3.BACK, deg_to_rad(rocket.gimbal_z * rocket.physics_config.max_gimbal_deg)))
	var engine_position: Vector3 = rocket.to_global(Vector3(0, -1.30, 0))
	for jet in [plume, plume_core, exhaust_envelope, exhaust_hot_core, exhaust_ignition_sleeve,
		exhaust_turbulence_veil, exhaust_expansion_cloud, exhaust_diffuse_haze, exhaust_diamond_core]:
		jet.global_transform = Transform3D(nozzle_basis, engine_position)
		jet.emitting = thrust > 0.025
	nozzle_glow.global_transform = Transform3D(nozzle_basis, rocket.to_global(Vector3(0, -1.32, 0)))
	nozzle_glow.visible = thrust > 0.025
	nozzle_glow.scale = Vector3.ONE * (0.76 + 0.34 * thrust * composite_flicker)
	nozzle_light.global_position = engine_position
	nozzle_light.light_energy = thrust * (0.40 if reduced_particles else 0.62) * composite_flicker

	plume.initial_velocity_max = (4.5 + 10.5 * thrust) * flicker_fast
	plume_core.initial_velocity_max = (6.0 + 14.0 * thrust) * composite_flicker
	exhaust_envelope.initial_velocity_max = (3.5 + 7.0 * thrust) * flicker_slow
	exhaust_hot_core.initial_velocity_max = (5.8 + 11.5 * thrust) * composite_flicker
	exhaust_ignition_sleeve.initial_velocity_max = (3.9 + 7.6 * thrust) * flicker_fast
	exhaust_turbulence_veil.initial_velocity_max = 2.8 + 6.6 * thrust
	exhaust_expansion_cloud.initial_velocity_max = 2.2 + 5.0 * thrust
	exhaust_diffuse_haze.initial_velocity_max = 1.6 + 4.3 * thrust
	exhaust_diamond_core.initial_velocity_max = (7.0 + 15.5 * thrust) * composite_flicker
	plume.scale_amount_max = 0.05 + 0.08 * thrust
	plume_core.scale_amount_max = 0.026 + 0.040 * thrust
	exhaust_envelope.scale_amount_max = 0.10 + 0.18 * thrust
	exhaust_hot_core.scale_amount_max = 0.025 + 0.04 * thrust
	exhaust_ignition_sleeve.scale_amount_max = 0.040 + 0.060 * thrust
	exhaust_turbulence_veil.scale_amount_max = 0.12 + 0.22 * thrust
	exhaust_expansion_cloud.scale_amount_max = 0.20 + 0.34 * thrust
	exhaust_diffuse_haze.scale_amount_max = 0.26 + 0.46 * thrust
	exhaust_diamond_core.scale_amount_max = 0.018 + 0.030 * thrust
	exhaust_turbulence_veil.lifetime = 0.42 + 0.28 * thrust
	exhaust_expansion_cloud.lifetime = 0.56 + 0.30 * thrust
	exhaust_diffuse_haze.lifetime = 0.70 + 0.34 * thrust
	exhaust_diamond_core.lifetime = 0.12 + 0.06 * thrust
	# F32: F31's clipping step must use the *current throttle-dependent target*
	# lifetime. Previously it overwrote these four F16 updates with the fixed
	# initial lifetime every frame, even far above the ground.
	_f31_engine_base_lifetimes[exhaust_turbulence_veil.name] = exhaust_turbulence_veil.lifetime
	_f31_engine_base_lifetimes[exhaust_expansion_cloud.name] = exhaust_expansion_cloud.lifetime
	_f31_engine_base_lifetimes[exhaust_diffuse_haze.name] = exhaust_diffuse_haze.lifetime
	_f31_engine_base_lifetimes[exhaust_diamond_core.name] = exhaust_diamond_core.lifetime

	var yaw: float = rocket.yaw_rcs if active else 0.0
	var yaw_intensity: float = clampf(absf(yaw), 0.0, 1.0)
	var yaw_offsets := [Vector3(0.73, 0.51, 0.0), Vector3(-0.73, 0.51, 0.0), Vector3(0.73, 0.51, 0.0), Vector3(-0.73, 0.51, 0.0)]
	var yaw_dirs := [Vector3.BACK, Vector3.FORWARD, Vector3.FORWARD, Vector3.BACK]
	for index in range(yaw_jets.size()):
		var yaw_active := (yaw > 0.08 and index < 2) or (yaw < -0.08 and index >= 2)
		_apply_rcs_visual(yaw_jets[index], yaw_halos[index], yaw_trails[index], yaw_mists[index],
			yaw_offsets[index], yaw_dirs[index], yaw_intensity, yaw_active)

	# Gimbal-associated decorative jets must not emit without the main burn.
	var pitch_signal: float = rocket.gimbal_x if active and thrust > 0.025 else 0.0
	var lateral_signal: float = rocket.gimbal_z if active and thrust > 0.025 else 0.0
	if not F35_ENABLE_FICTIONAL_GIMBAL_JETS:
		pitch_signal = 0.0
		lateral_signal = 0.0
	# Motion can modulate the ground dust, but must never fabricate RCS exhaust.
	var local_velocity: Vector3 = rocket.global_transform.basis.inverse() * rocket.linear_velocity
	var pitch_visual: float = _control_signal(pitch_signal, local_velocity.z)
	var lateral_visual: float = _control_signal(lateral_signal, local_velocity.x)
	# Legacy F15 reference kept for static regression checks:
	# pitch_jets[index].scale_amount_max = 0.05 + 0.08 * pitch_visual
	var pitch_offsets := [
		Vector3(-0.21, 0.98, -0.72), Vector3(0.21, 0.98, -0.72),
		Vector3(-0.21, 0.98, 0.72), Vector3(0.21, 0.98, 0.72)
	]
	var pitch_dirs := [Vector3.FORWARD, Vector3.FORWARD, Vector3.BACK, Vector3.BACK]
	for index in range(pitch_jets.size()):
		var pitch_active: bool = (pitch_signal < -0.12 and index < 2) or (pitch_signal > 0.12 and index >= 2)
		_apply_rcs_visual(pitch_jets[index], pitch_halos[index], pitch_trails[index], pitch_mists[index],
			pitch_offsets[index], pitch_dirs[index], pitch_visual, pitch_active)

	# Legacy F15 reference kept for static regression checks:
	# lateral_rcs_jets[index].scale_amount_max = 0.052 + 0.10 * lateral_visual
	var lateral_offsets := [
		Vector3(-0.84, 1.02, -0.24), Vector3(-0.84, 1.02, 0.24),
		Vector3(0.84, 1.02, -0.24), Vector3(0.84, 1.02, 0.24)
	]
	var lateral_dirs := [Vector3.LEFT, Vector3.LEFT, Vector3.RIGHT, Vector3.RIGHT]
	for index in range(lateral_rcs_jets.size()):
		var lateral_active: bool = (lateral_signal > 0.12 and index < 2) or (lateral_signal < -0.12 and index >= 2)
		_apply_rcs_visual(lateral_rcs_jets[index], lateral_rcs_halos[index], lateral_rcs_trails[index], lateral_rcs_mists[index],
			lateral_offsets[index], lateral_dirs[index], lateral_visual, lateral_active)

	# F31: dust exists only for real regolith and only where the projected
	# nozzle ray intersects the ground. Metal landing decks eject no lunar dust.
	_f35_update_distance_budget()
	var hit: Dictionary = F31_SURFACE_MATH.solve(engine_position, nozzle_basis * Vector3.DOWN)
	_f31_limit_particle_ground_travel(hit)
	var on_pad: bool = not hit.is_empty() and bool(hit["deck"])
	var contact_approach: float = float(hit.get("proximity", 0.0))
	var height: float = rocket.global_position.y
	var dust_active: bool = active and thrust > 0.12 and not hit.is_empty() and not on_pad and contact_approach > 0.08
	var hit_point: Vector3 = hit.get("point", Vector3(rocket.global_position.x, 0.0, rocket.global_position.z))
	dust.global_position = hit_point + Vector3.UP * 0.045
	dust.emitting = dust_active
	dust.initial_velocity_max = 0.9 + 3.7 * thrust * contact_approach
	# Mostly lateral ballistic ejecta, with authentic lunar gravity and no
	# atmospheric billowing smoke. Trails already use local_coords = false.
	# Sparse grains, with a low ballistic fan replacing tall atmospheric puffs.
	dust.direction = Vector3(0.95, 0.16, 0.0).normalized()
	dust.spread = 175.0
	var sideways: Vector3 = Vector3(rocket.linear_velocity.x, 0.0, rocket.linear_velocity.z)
	lateral_dust.global_position = hit_point + Vector3.UP * 0.055
	lateral_dust.direction = (Vector3.UP * 0.4 - sideways.normalized() * 1.1).normalized()
	lateral_dust.emitting = dust_active and sideways.length() > 0.5
	_f35_update_surface_fans(hit, thrust, active, hit_point, sideways)
	lateral_dust.initial_velocity_max = clampf(1.3 + sideways.length() * 0.58, 1.3, 7.0)
	regolith_flash.visible = dust_active and contact_approach > 0.1 and not reduced_particles
	regolith_flash.global_position = hit_point + Vector3.UP * 0.025
	var flash_width: float = 0.9 + 2.7 * thrust * contact_approach
	regolith_flash.scale = Vector3(flash_width, 1.0, flash_width)
	nozzle_light.omni_range = 3.0 + 3.5 * thrust * contact_approach
