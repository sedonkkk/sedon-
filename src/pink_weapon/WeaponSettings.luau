--!nonstrict
-- Settings for the OWNED Studio weapon. These are not Da Hood weapon facts.
local WeaponSettings = {}
local defaults = {
	WeaponName = "SEDWARE Revolver", Range = 400, Cooldown = 0.35, Damage = 25,
	RequestMaxAge = 0.6, ClockTolerance = 0.05, MaxOriginDistance = 3,
	MaxAimDistance = 2000, MaxSessionsPerPlayer = 64,
	MaxProjectiles = 64, MaxProjectilesPerPlayer = 8,
}
local allowedParts = {}
for _, name in {
	"HumanoidRootPart", "Head", "Torso", "UpperTorso", "LowerTorso",
	"Left Arm", "Right Arm", "Left Leg", "Right Leg", "LeftHand", "RightHand",
	"LeftFoot", "RightFoot", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm",
	"LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg",
} do allowedParts[name] = true end

local limits = {
	Range = { 1, 2000 }, Cooldown = { 0.05, 10 }, Damage = { 0, 100 },
	RequestMaxAge = { 0.05, 2 }, ClockTolerance = { 0, 0.2 }, MaxOriginDistance = { 0, 5 },
	MaxAimDistance = { 1, 10000 }, MaxSessionsPerPlayer = { 1, 128 },
	MaxProjectiles = { 1, 256 }, MaxProjectilesPerPlayer = { 1, 32 },
}
function WeaponSettings.new(overrides)
	local config = table.clone(defaults)
	if overrides ~= nil then
		assert(type(overrides) == "table" and getmetatable(overrides) == nil, "Weapon settings must be a plain table")
		for key, value in overrides do
			assert(defaults[key] ~= nil, "Unknown weapon setting: " .. tostring(key))
			config[key] = value
		end
	end
	assert(type(config.WeaponName) == "string" and #config.WeaponName > 0 and #config.WeaponName <= 64, "Invalid WeaponName")
	for key, bounds in limits do
		local value = config[key]
		assert(type(value) == "number" and value == value and value >= bounds[1] and value <= bounds[2], "Invalid " .. key)
	end
	assert(config.MaxSessionsPerPlayer % 1 == 0, "MaxSessionsPerPlayer must be an integer")
	assert(config.MaxProjectiles%1==0 and config.MaxProjectilesPerPlayer%1==0,"Projectile capacities must be integers")
	config.AllowedParts = table.freeze(table.clone(allowedParts))
	return table.freeze(config)
end
return WeaponSettings
