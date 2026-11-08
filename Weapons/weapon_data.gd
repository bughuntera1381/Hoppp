extends RefCounted
## Weapon stat table. Add a new weapon: append a Dictionary here and a model builder in weapon.gd.

const WEAPONS := [
	{
		"name": "R-301 CARBINE", "damage": 14.0, "rpm": 660.0, "auto": true,
		"mag": 28, "reserve": 112, "reload": 1.9,
		"spread_hip": 1.1, "spread_ads": 0.25, "bloom": 0.22, "bloom_max": 2.2, "bloom_recover": 4.0,
		"recoil_pitch": 0.55, "recoil_yaw": 0.28, "range": 120.0, "zoom_fov": 55.0,
	},
	{
		"name": "P2020 PISTOL", "damage": 21.0, "rpm": 420.0, "auto": false,
		"mag": 14, "reserve": 70, "reload": 1.3,
		"spread_hip": 0.9, "spread_ads": 0.2, "bloom": 0.5, "bloom_max": 2.0, "bloom_recover": 4.0,
		"recoil_pitch": 1.1, "recoil_yaw": 0.35, "range": 90.0, "zoom_fov": 65.0,
	},
]
