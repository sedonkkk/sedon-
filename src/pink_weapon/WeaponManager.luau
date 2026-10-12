--!nonstrict
-- One selection/Memory session and one shot-ID stream across compatible Tools.
-- Registration is explicit: this never discovers or hooks foreign weapons.
local ClientController=if script then require(script.Parent.ClientController) else require("./ClientController")
local WeaponProfiles=if script then require(script.Parent.WeaponProfiles) else require("./WeaponProfiles")
local WeaponManager={}
WeaponManager.__index=WeaponManager
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function disconnect(list)
 for _,connection in list do pcall(function() connection:Disconnect() end) end
 table.clear(list)
end
function WeaponManager.new(options)
 assert(type(options)=="table" and type(options.api)=="table" and type(options.api.SetWeaponProfile)=="function","Current SEDWARE profile API required")
 assert(type(options.api.SetPredictionOrigin)=="function","Current SEDWARE muzzle-origin API required")
 for _,name in {"clock","send","getOrigin","getCameraAim","isEquipped"} do assert(type(options[name])=="function",name.." callback required") end
 local self=setmetatable({options=options,api=options.api,profiles={},controllers={},tools={},active=nil,
  held=false,nextFire=-math.huge,destroyed=false},WeaponManager)
 local configured=options.profiles or WeaponProfiles.defaults()
 for id,profile in configured do self:register(id,profile) end
 local session=self.api.session
 if session then
  self.saved={slot=session.config.WeaponProfile,custom=table.clone(session.config.Profiles.Custom),
   label=session.prediction and session.prediction.weaponProfileLabel,origin=session.predictionOriginProvider}
 end
 local function origin() return if self.active then options.getOrigin(self.active.tool) else nil end
 local adapter=options.adapter or self.api.CreateShotAdapter(nil,{getOrigin=origin,maxAge=8})
 self.client=ClientController.new({api=self.api,clock=options.clock,sessionId=options.sessionId,adapter=adapter,
  getOrigin=origin,getCameraAim=function() return if self.active then options.getCameraAim(self.active.profile) else nil end,
  isEquipped=function() return self.active~=nil and options.isEquipped(self.active.tool)==true end,
  getWeapon=function() return if self.active then {id=self.active.profile.Id,timeout=if self.active.profile.Kind=="Projectile" then self.active.profile.Lifetime+2 else 2} else nil end,
  send=function(request)
   local profile=self.profiles[request.weaponId]
   assert(profile,"Unregistered weapon controller")
   local context={profile=profile,aimpoint=request.aimpoint,mode=request.mode,
    targetUserId=request.targetUserId,targetCharacter=request.targetCharacter}
   local controller=self.controllers[request.weaponId] or options.send
   return controller(request,context)
  end,
  onStatus=options.onStatus,maxPending=64,timeout=2})
 local originSet,problem=self.api.SetPredictionOrigin(origin)
 if not originSet then self.client:destroy();error("Cannot set owned muzzle origin: "..tostring(problem)) end
 return self
end
function WeaponManager:register(id,profile)
 assert(not self.destroyed,"WeaponManager is destroyed")
 assert(self.profiles[id]==nil,"Weapon profile already registered")
 local count=0;for _ in self.profiles do count+=1 end
 assert(count<64,"Too many registered weapon profiles")
 self.profiles[id]=WeaponProfiles.normalize(id,profile)
 return self.profiles[id]
end
function WeaponManager:registerController(id,callback)
 assert(not self.destroyed and self.profiles[id],"Registered weapon profile required")
 assert(type(callback)=="function","Owned controller callback required")
 self.controllers[id]=callback
end
function WeaponManager:equip(tool,id)
 if self.destroyed then return false,"destroyed" end
 local profile=self.profiles[id]
 if not profile then return false,"unsupported-weapon" end
 if tool==nil or self.options.isEquipped(tool)~=true then return false,"weapon-not-equipped" end
 if self.active and self.active.tool==tool and self.active.profile.Id==id then return true end
 local ok,message=self.api.SetWeaponProfile("Custom",WeaponProfiles.prediction(profile),id)
 if not ok then return false,"prediction-profile-rejected: "..tostring(message) end
 self.held=false
 self.active={tool=tool,profile=profile}
 if self.options.onWeaponChanged then pcall(self.options.onWeaponChanged,profile,tool) end
 return true
end
function WeaponManager:unequip(tool)
 if self.active and (tool==nil or self.active.tool==tool) then self.held=false;self.active=nil end
 -- Selection and Memory deliberately belong to SEDWARE, not the equipped Tool.
end
function WeaponManager:fire()
 if self.destroyed then return nil,"destroyed" end
 if not self.active then return nil,"no-compatible-weapon" end
 if self.options.isEquipped(self.active.tool)~=true then self:unequip();return nil,"weapon-not-equipped" end
 local now=self.options.clock()
 if not finite(now) then return nil,"invalid-clock" end
 if now+1e-7<self.nextFire then return nil,"client-cooldown" end
 local profile=self.active.profile
 local request,message=self.client:fire()
 if request then self.nextFire=now+profile.Cooldown end
 return request,message
end
function WeaponManager:press()
 if self.destroyed or not self.active then return nil,"no-compatible-weapon" end
 self.held=self.active.profile.Automatic
 return self:fire()
end
function WeaponManager:release() self.held=false end
function WeaponManager:step(now)
 if self.destroyed then return end
 now=now or self.options.clock()
 if not finite(now) then self.held=false;return end
 self.client:step(now)
 if self.held and self.active and self.active.profile.Automatic and now+1e-7>=self.nextFire then
  local cooldown=self.active.profile.Cooldown
  local request,problem=self:fire()
  -- No catch-up bursts. A failed held shot backs off rather than spamming.
  if not request then self.nextFire=now+cooldown end
 end
end
function WeaponManager:track(tool,id)
 assert(not self.destroyed and self.profiles[id],"Compatible registered Tool required")
 if self.tools[tool] then return end
 assert(tool:IsA("Tool"),"Only an authorized Tool can be tracked")
 local bindings={};self.tools[tool]=bindings
 local function bind(signal,callback)
  local connection=signal:Connect(callback)
  assert(connection and connection.Connected,"Weapon Tool event failed to connect")
  table.insert(bindings,connection)
 end
 local function equipped()
  local ok,message=self:equip(tool,id)
  if not ok and self.options.onStatus then pcall(self.options.onStatus,"ClientRejected",{reason=message}) end
  return ok
 end
 bind(tool.Equipped,equipped)
 bind(tool.Unequipped,function() self:unequip(tool) end)
 bind(tool.Activated,function()
  if self.options.isEquipped(tool)==true and equipped() then self:press() end
 end)
 bind(tool.Deactivated,function() if self.active and self.active.tool==tool then self:release() end end)
 bind(tool.AncestryChanged,function() if self.active and self.active.tool==tool and self.options.isEquipped(tool)~=true then self:unequip(tool) end end)
 bind(tool.Destroying,function() self:untrack(tool) end)
 if self.options.isEquipped(tool)==true then equipped() end
end
function WeaponManager:untrack(tool)
 self:unequip(tool)
 local list=self.tools[tool]
 if list then disconnect(list);self.tools[tool]=nil end
end
function WeaponManager:receive(response)
 if self.destroyed then return nil,"destroyed" end
 return self.client:receive(response)
end
function WeaponManager:summary() return self.client:summary() end
function WeaponManager:destroy()
 if self.destroyed then return end
 self.destroyed=true;self.held=false;self.active=nil
 for tool in self.tools do self:untrack(tool) end
 self.client:destroy()
 if self.saved and self.api.session and not self.api.session.destroyed then
  self.api.SetWeaponProfile("Custom",self.saved.custom)
  self.api.SetWeaponProfile(self.saved.slot,nil,self.saved.label)
  self.api.SetPredictionOrigin(self.saved.origin)
 end
 table.clear(self.profiles);table.clear(self.controllers)
 self.options=nil;self.api=nil
end
return WeaponManager
