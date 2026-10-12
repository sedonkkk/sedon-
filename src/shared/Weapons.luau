--!nonstrict
-- Lab profiles, NOT measured properties of any third-party game.
-- Roblox gravity is deliberately disabled for ProjectileLab initially: calibration
-- starts with straight flight; setting gravity > 0 enables ballistic compensation.
local Weapons = {}
local profiles = {
 RevolverLab = table.freeze({name="RevolverLab",kind="hitscan",speed=0,gravity=0,
  cooldown=0.35,spreadRadians=0,radius=0,latencyOffsetSeconds=0}),
 ProjectileLab = table.freeze({name="ProjectileLab",kind="projectile",speed=180,gravity=0,
  cooldown=0.25,spreadRadians=0,radius=0.12,latencyOffsetSeconds=0}),
}
function Weapons.get(name)
 return profiles[name]
end
function Weapons.names()
 return {"RevolverLab", "ProjectileLab"}
end
return table.freeze(Weapons)
