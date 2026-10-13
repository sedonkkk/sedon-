--!nonstrict
local ESPRenderer=if script then require(script.Parent.ESPRenderer) else require("./ESPRenderer")
local ESPManager={}
ESPManager.__index=ESPManager
function ESPManager.new(config,report,registry)
 local self=setmetatable({config=config,report=report,registry=registry,renderers={},destroyed=false,
  stats={updates=0,created=0,lastSeconds=0,maxSeconds=0,visible=0,considered=0,registered=0,inRange=0,onScreen=0,occluded=0,notReady=0,outOfRange=0,offscreen=0,active=0,raycasts=0,totalSeconds=0}},ESPManager)
 if config.ESPUsername~="" then self.selectedUsername=string.lower(config.ESPUsername) end
 return self
end
function ESPManager:applyTarget(username)
 local entry=self.registry:lookup(username)
 if not entry or entry.player==self.report.player then self.selectedUsername=nil;self:refresh();return false,"Player Username no encontrado" end
 self.selectedUsername=entry.username;self:refresh();return true
end
function ESPManager:clearTarget() self.selectedUsername=nil;self:refresh() end
function ESPManager:refresh() self.nextUpdate=nil;self:_trim();if not self.config.ESP or (not self.config.Hitboxes and not self.config.Names) then self.stats.visible=0;self.stats.active=0 end end
function ESPManager:_selected(entry)
 return entry.player~=self.report.player and (self.config.ESPTargetMode=="All"
  or (self.selectedUsername~=nil and entry.username==self.selectedUsername))
end
function ESPManager:_trim()
 for player,renderer in self.renderers do
  local entry=self.registry.entries[player]
  if not self.config.ESP or not entry or not self:_selected(entry) or (not self.config.Hitboxes and not self.config.Names) then
   renderer:destroy();self.renderers[player]=nil
  end
 end
end
function ESPManager:changed(kind,entry)
 local renderer=self.renderers[entry.player]
 if renderer and (kind=="CharacterRemoving" or kind=="Died") then renderer:hide() end
 self:refresh()
end
function ESPManager:update(now)
 if self.destroyed then return end
 if not self.config.ESP or (not self.config.Hitboxes and not self.config.Names) then return end
 if self.nextUpdate and now<self.nextUpdate then return end
 local hz=if self.config.ESPLowPerformanceMode then math.min(self.config.ESPUpdateHz,10) else self.config.ESPUpdateHz
 self.nextUpdate=now+1/hz
 local started=os.clock();self.stats.updates+=1;for _,key in {"visible","considered","inRange","onScreen","occluded","notReady","outOfRange","offscreen","active","raycasts"} do self.stats[key]=0 end
 self.stats.registered=#self.registry.list-(if self.registry.entries[self.report.player] then 1 else 0)
 self:_trim()
 local camera=self.report.world.CurrentCamera
 if not camera then for _,renderer in self.renderers do renderer:hide() end;self.stats.reason="CurrentCamera unavailable";return end
 if not self.params then
  assert(RaycastParams and type(RaycastParams.new)=="function","ESP requires RaycastParams")
  self.params=RaycastParams.new();self.params.FilterType=Enum.RaycastFilterType.Exclude;self.params.IgnoreWater=true
 end
 self.params.FilterDescendantsInstances=if self.report.player.Character then {self.report.player.Character} else {}
 for _,entry in self.registry.list do
  if self:_selected(entry) then
   self.stats.considered+=1
   local ready=entry.character and entry.character:IsDescendantOf(self.report.world)
    and entry.humanoid and entry.humanoid.Health>0 and entry.root and (entry.head or entry.root)
   local visible=false
   if ready then
    local position=(entry.head or entry.root).Position
    local delta=position-camera.CFrame.Position
    if delta.Magnitude<=self.config.ESPMaxDistance then
     self.stats.inRange+=1
     local projected,onScreen=camera:WorldToViewportPoint(position)
     if onScreen and projected.Z>0 then
      self.stats.onScreen+=1;self.stats.raycasts+=1
      local hit=self.report.world:Raycast(camera.CFrame.Position,delta,self.params)
      visible=hit==nil or (hit.Instance and hit.Instance:IsDescendantOf(entry.character))
      if not visible then self.stats.occluded+=1 end
     else self.stats.offscreen+=1 end
    else self.stats.outOfRange+=1 end
   else self.stats.notReady+=1 end
   local renderer=self.renderers[entry.player]
   -- No instances for players that have never become visible.
   if not renderer and visible then renderer=ESPRenderer.new(self.report.playerGui,entry,self.config);self.renderers[entry.player]=renderer end
   if renderer then
    local before=renderer.created
    if ready then renderer:sync(visible) else renderer:hide() end
    self.stats.created+=renderer.created-before
   end
   if visible then
    self.stats.visible+=1
    if renderer.box and renderer.box.Visible then self.stats.active+=1 end
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
 table.clear(self.renderers)
end
return ESPManager
