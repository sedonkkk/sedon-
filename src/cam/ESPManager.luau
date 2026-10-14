--!nonstrict
local ESPRenderer=if script then require(script.Parent.ESPRenderer) else require("./ESPRenderer")
local Access=if script then require(script.Parent.ESPAccess) else require("./ESPAccess")
local ESPManager={}
ESPManager.__index=ESPManager
function ESPManager.new(config,report,registry)
 local self=setmetatable({config=config,report=report,registry=registry,renderers={},observations={},destroyed=false,
  stats={updates=0,created=0,lastSeconds=0,maxSeconds=0,visible=0,considered=0,registered=0,inRange=0,onScreen=0,occluded=0,notReady=0,outOfRange=0,offscreen=0,active=0,raycasts=0,totalSeconds=0,invalidRoot=0,invalidHead=0,
   mode=config.ESPOcclusionMode,maxDistance=config.ESPMaxDistance,unlimitedRange=config.ESPUnlimitedRange}},ESPManager)
 if config.ESPUsername~="" then self.selectedUsername=string.lower(config.ESPUsername) end
 return self
end
function ESPManager:applyTarget(username)
 local entry=self.registry:lookup(username)
 if not entry or entry.player==self.report.player then self.selectedUsername=nil;self:refresh();return false,"Player Username no encontrado" end
 self.selectedUsername=entry.username;self:refresh();return true
end
function ESPManager:clearTarget() self.selectedUsername=nil;self:refresh() end
function ESPManager:refresh()
 self.stats.mode=self.config.ESPOcclusionMode;self.stats.maxDistance=self.config.ESPMaxDistance;self.stats.unlimitedRange=self.config.ESPUnlimitedRange
 self.nextUpdate=nil;table.clear(self.observations);for _,r in self.renderers do r.nextUpdate=nil end;self:_trim()
 if not self.config.ESP or (not self.config.Hitboxes and not self.config.Names) then self.stats.visible=0;self.stats.active=0 end
end
function ESPManager:_selected(entry)
 return entry.player~=self.report.player and (self.config.ESPTargetMode=="All"
  or (self.selectedUsername~=nil and entry.username==self.selectedUsername))
end
function ESPManager:_trim()
 for player in self.observations do if not self.registry.entries[player] or not self.config.ESP then self.observations[player]=nil end end
 for player,renderer in self.renderers do
  local entry=self.registry.entries[player]
  if not self.config.ESP or not entry or not self:_selected(entry) or (not self.config.Hitboxes and not self.config.Names) then
   renderer:destroy();self.renderers[player]=nil
  end
 end
 if self.layer and next(self.renderers)==nil then self.layer:Destroy();self.layer=nil end
end
function ESPManager:changed(kind,entry)
 self.observations[entry.player]=nil
 local renderer=self.renderers[entry.player]
 if renderer and (kind=="CharacterRemoving" or kind=="Died") then renderer:hide() end
 self:refresh()
end
function ESPManager:update(now)
 if self.destroyed then return end
 if not self.config.ESP or (not self.config.Hitboxes and not self.config.Names) then return end
 if (self.config.ESPOcclusionMode=="AlwaysOnTop" or self.config.ESPUnlimitedRange) and not Access.allowed(self.config,self.report) then error("Extended/AlwaysOnTop ESP requires an authorized context") end
 if self.nextUpdate and now<self.nextUpdate then return end
 local hz=if self.config.ESPLowPerformanceMode then math.min(self.config.ESPUpdateHz,10) else self.config.ESPUpdateHz
 self.nextUpdate=now+1/hz
 local started=os.clock();self.stats.updates+=1;for _,key in {"visible","considered","inRange","onScreen","occluded","notReady","outOfRange","offscreen","active","raycasts","invalidRoot","invalidHead"} do self.stats[key]=0 end
 self.stats.registered=#self.registry.list-(if self.registry.entries[self.report.player] then 1 else 0)
 self:_trim()
 if self.config.ESPOcclusionMode~="AlwaysOnTop" and self.layer then self.layer:Destroy();self.layer=nil end
 local camera=self.report.world.CurrentCamera
 if not camera then for _,renderer in self.renderers do renderer:hide() end;self.stats.reason="CurrentCamera unavailable";return end
 if self.config.ESPOcclusionMode=="VisibleOnly" and not self.params then
  assert(RaycastParams and type(RaycastParams.new)=="function","ESP requires RaycastParams")
  self.params=RaycastParams.new();self.params.FilterType=Enum.RaycastFilterType.Exclude;self.params.IgnoreWater=true
 end
 if self.params then self.params.FilterDescendantsInstances=if self.report.player.Character then {self.report.player.Character} else {} end
 for _,entry in self.registry.list do
  if self:_selected(entry) then
   self.stats.considered+=1
   -- Registry events usually refresh these references immediately. Validate
   -- ancestry here as well: streaming/respawn must never draw stale parts.
   local root=entry.character and entry.root and entry.root:IsA("BasePart") and entry.root:IsDescendantOf(entry.character) and entry.root
   local head=entry.character and entry.head and entry.head:IsA("BasePart") and entry.head:IsDescendantOf(entry.character) and entry.head
   if entry.root and not root then self.stats.invalidRoot+=1 end
   if entry.head and not head then self.stats.invalidHead+=1 end
   local adornment=head or root
   local ready=entry.character and entry.character:IsDescendantOf(self.report.world)
    and entry.humanoid and entry.humanoid.Health>0 and root and adornment
   local visible=false
   if ready then
    local position=adornment.Position
    local delta=position-camera.CFrame.Position
    if self.config.ESPUnlimitedRange or delta.Magnitude<=self.config.ESPMaxDistance then
     self.stats.inRange+=1
     local observation=self.observations[entry.player]
     if not observation or now>=observation.nextCheck or observation.character~=entry.character then
      local projected,onScreen=camera:WorldToViewportPoint(position)
      local screen=onScreen and projected.Z>0
      local hit
      if screen and self.config.ESPOcclusionMode=="VisibleOnly" then
       hit=self.report.world:Raycast(camera.CFrame.Position,delta,self.params);self.stats.raycasts+=1
      end
      observation=observation or {};self.observations[entry.player]=observation
      observation.screen=screen;observation.visible=screen and (hit==nil or (hit.Instance and hit.Instance:IsDescendantOf(entry.character)))
      observation.character=entry.character
      observation.nextCheck=now+1/(if delta.Magnitude>self.config.ESPFarDistance then math.min(self.config.ESPFarUpdateHz,hz) else hz)
     end
     if observation.screen then
      self.stats.onScreen+=1;visible=observation.visible
      if not visible then self.stats.occluded+=1 end
     else self.stats.offscreen+=1 end
    else self.stats.outOfRange+=1 end
   else self.stats.notReady+=1 end
   local renderer=self.renderers[entry.player]
   -- No instances for players that have never become visible.
   if visible and self.config.ESPOcclusionMode=="AlwaysOnTop" and not self.layer then
    self.layer=Instance.new("ScreenGui");self.layer.Name="SEDWAREAuthorizedESP";self.layer.IgnoreGuiInset=true
    self.layer.ResetOnSpawn=false;self.layer.DisplayOrder=40;self.layer.Parent=self.report.playerGui
   end
   if not renderer and visible then
    renderer=ESPRenderer.new(self.report.playerGui,entry,self.config,self.layer,self.report.world);self.renderers[entry.player]=renderer
   end
   if renderer then
    local before=renderer.created
    if ready then
     local cameraDistance=(adornment.Position-camera.CFrame.Position).Magnitude
     local due=not renderer.nextUpdate or now>=renderer.nextUpdate
     if not visible then renderer:hide();renderer.nextUpdate=nil
     elseif due then
      renderer.layer=self.layer;renderer:sync(true)
      renderer.nextUpdate=now+1/(if cameraDistance>self.config.ESPFarDistance then math.min(self.config.ESPFarUpdateHz,hz) else hz)
     end
    else renderer:hide() end
    self.stats.created+=renderer.created-before
   end
   if visible then
    self.stats.visible+=1
    if (renderer.box and renderer.box.Visible) or (renderer.screenBox and renderer.screenBox.Visible) then self.stats.active+=1 end
    if renderer.billboard and renderer.billboard.Enabled then self.stats.active+=1 end
   end
  end
 end
 self.stats.reason=if self.stats.visible>0 then "Visible candidates" elseif self.stats.considered==0 then "No matching players" else "All candidates rejected; see counters"
 self.stats.lastSeconds=os.clock()-started;self.stats.totalSeconds+=self.stats.lastSeconds;self.stats.maxSeconds=math.max(self.stats.maxSeconds,self.stats.lastSeconds)
end
function ESPManager:destroy()
 if self.destroyed then return end
 self.destroyed=true
 for _,renderer in self.renderers do renderer:destroy() end
 table.clear(self.renderers);table.clear(self.observations)
 if self.layer then self.layer:Destroy();self.layer=nil end
end
return ESPManager
