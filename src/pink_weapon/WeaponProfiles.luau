--!nonstrict
-- Configurable OWNED weapon definitions. None describe weapons in Da Hood.
local WeaponProfiles = {}
local base = {
 Name="SEDWARE Custom", Family="Custom", Kind="Hitscan", Automatic=false,
 Range=400, Cooldown=0.35, Damage=25, Pellets=1, SpreadDegrees=0,
 Speed=0, Gravity=0, Lifetime=3,
 PredictionXOffset=0, PredictionYOffset=0, LatencyOffsetSeconds=0,
 CloseOffset=0, MediumOffset=0, LongOffset=0,
}
local limits = {
 Range={1,2000}, Cooldown={0.05,10}, Damage={0,100}, Pellets={1,32}, SpreadDegrees={0,20},
 Speed={0,3000}, Gravity={0,500}, Lifetime={0.1,5},
 PredictionXOffset={-0.2,0.2}, PredictionYOffset={-0.2,0.2}, LatencyOffsetSeconds={-0.2,0.2},
 CloseOffset={-0.2,0.2}, MediumOffset={-0.2,0.2}, LongOffset={-0.2,0.2},
}
local examples = {
 Revolver={Name="SEDWARE Revolver",Family="Revolver",Cooldown=0.35,Damage=25},
 Pistol={Name="SEDWARE Pistol",Family="Pistol",Cooldown=0.2,Damage=15,Range=300},
 Shotgun={Name="SEDWARE Shotgun",Family="Shotgun",Cooldown=0.8,Damage=6,Range=180,Pellets=8,SpreadDegrees=3},
 Rifle={Name="SEDWARE Rifle",Family="Rifle",Cooldown=0.3,Damage=30,Range=600,SpreadDegrees=0.15},
 Automatic={Name="SEDWARE Automatic",Family="Automatic",Automatic=true,Cooldown=0.12,Damage=8,Range=400,SpreadDegrees=1},
 Projectile={Name="SEDWARE Projectile",Family="Projectile",Kind="Projectile",Cooldown=0.7,Damage=35,
  Range=250,Speed=160,Gravity=196.2,Lifetime=3},
}
function WeaponProfiles.validId(value)
 return type(value)=="string" and #value>=1 and #value<=40 and string.match(value,"^[A-Za-z][A-Za-z0-9_]*$")~=nil
end
function WeaponProfiles.normalize(id,overrides)
 assert(WeaponProfiles.validId(id),"Invalid owned weapon ID")
 assert(type(overrides)=="table" and getmetatable(overrides)==nil,"Weapon profile must be a plain table")
 local result=table.clone(base)
 for key,value in overrides do
  assert(base[key]~=nil or key=="Id","Unknown weapon profile field: "..tostring(key))
  if key=="Id" then assert(value==id,"Profile ID mismatch") else result[key]=value end
 end
 for _,key in {"Name","Family"} do assert(type(result[key])=="string" and #result[key]>0 and #result[key]<=64,"Invalid profile "..key) end
 assert(result.Kind=="Hitscan" or result.Kind=="Projectile","Invalid weapon kind")
 assert(type(result.Automatic)=="boolean","Invalid Automatic flag")
 for key,bounds in limits do
  local value=result[key]
  assert(type(value)=="number" and value==value and value>=bounds[1] and value<=bounds[2],"Invalid profile "..key)
 end
 assert(result.Pellets%1==0,"Pellets must be an integer")
 if result.Kind=="Projectile" then
  assert(result.Speed>0,"Physical projectile requires positive Speed")
  assert(result.Pellets==1,"This physical projectile controller accepts one projectile per shot")
 else
  assert(result.Speed==0 and result.Gravity==0,"Hitscan must not claim projectile speed or gravity")
 end
 result.Id=id
 return table.freeze(result)
end
function WeaponProfiles.defaults()
 local result={}
 for id,profile in examples do result[id]=WeaponProfiles.normalize(id,profile) end
 return result
end
function WeaponProfiles.prediction(profile)
 return {Kind=profile.Kind,Speed=profile.Speed,Gravity=profile.Gravity,
  PredictionXOffset=profile.PredictionXOffset,PredictionYOffset=profile.PredictionYOffset,
  LatencyOffsetSeconds=profile.LatencyOffsetSeconds,CloseOffset=profile.CloseOffset,
  MediumOffset=profile.MediumOffset,LongOffset=profile.LongOffset}
end
return WeaponProfiles
