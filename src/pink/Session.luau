--!nonstrict
-- Public client APIs only. Selection and prediction never write camera,
-- character rotation, mouse state, or any experience's weapon communications.
local Config = if script then require(script.Parent.Config) else require("./Config")
local Prediction = if script then require(script.Parent.Prediction) else require("./Prediction")
local ModeDetector = if script then require(script.Parent.ModeDetector) else require("./ModeDetector")
local Selection = if script then require(script.Parent.Selection) else require("./Selection")
local Overlay = if script then require(script.Parent.Overlay) else require("./Overlay")
local Runtime = if script then require(script.Parent.Runtime) else require("./Runtime")
local ShotAdapter = if script then require(script.Parent.ShotAdapter) else require("./ShotAdapter")
local Session = {}
Session.__index = Session
local OWNER_NAME = "PinkDotLock_Owner_v1"
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function vector(v) return v and finite(v.X) and finite(v.Y) and finite(v.Z) end
local function disconnect(list)
 for _, c in list do pcall(function() c:Disconnect() end) end
 table.clear(list)
end
local function connect(list, signal, callback,label)
 label=label or "Event"
 local c = signal:Connect(callback)
 assert(c and type(c.Disconnect)=="function",label.." did not return a disconnectable connection")
 table.insert(list,c)
 assert(c.Connected==true,label.." connection is not active")
 return c
end

function Session:_clock()
 local t=self.world:GetServerTimeNow()
 assert(finite(t),"Invalid client clock")
 return t
end
function Session:_origin()
 local character=self.player.Character
 local head=character and character:FindFirstChild("Head")
 if head and head:IsA("BasePart") and vector(head.Position) then return head.Position end
 local root=character and character:FindFirstChild("HumanoidRootPart")
 if root and root:IsA("BasePart") and vector(root.Position) then return root.Position end
 local camera=self.world.CurrentCamera
 return camera and camera.CFrame and camera.CFrame.Position
end
function Session:_targetData(player)
 if self.destroyed then return nil,"session unloaded" end
 if not player then return nil,"no player" end
 if player==self.player then return nil,"local player" end
 if player.Parent~=self.services.Players then return nil,"player removed" end
 local character=player.Character
 if not character or not character:IsDescendantOf(self.world) then return nil,"character absent" end
 local humanoid=character:FindFirstChildOfClass("Humanoid")
 local part=character:FindFirstChild(self.config.TargetPart)
 if not humanoid or not finite(humanoid.Health) or humanoid.Health<=0 then return nil,"humanoid dead or absent" end
 if not part or not part:IsA("BasePart") or not part:IsDescendantOf(character) or not vector(part.Position) then return nil,"target part invalid" end
 local origin=self:_origin()
 if not vector(origin) then return nil,"origin unavailable" end
 local distance=(part.Position-origin).Magnitude
 if not finite(distance) or distance>self.config.MaxDistance then return nil,"distance exceeds MaxDistance" end
 return {player=player,character=character,part=part,humanoid=humanoid,distanceStuds=distance,valid=true}
end
function Session:IsValidTarget(player)
 return self:_targetData(player)~=nil
end
function Session:_visible(candidate)
 if not self.config.VisibilityCheck then return true end
 local origin=self:_origin()
 if not vector(origin) then return false end
 self.rayParams.FilterDescendantsInstances=if self.player.Character then {self.player.Character} else {}
 local direction=candidate.part.Position-origin
 if direction.Magnitude<=0.001 then return true end
 local result=self.world:Raycast(origin,direction,self.rayParams)
 return result==nil or (result.Instance~=nil and result.Instance:IsDescendantOf(candidate.character))
end
function Session:_mode(t,camera)
 local character=self.player.Character
 local humanoid=character and character:FindFirstChildOfClass("Humanoid")
 local head=character and character:FindFirstChild("Head")
 local cameraPosition=camera.CFrame and camera.CFrame.Position
 local focusPosition=camera.Focus and camera.Focus.Position
 local headDistance=if head and vector(head.Position) and vector(cameraPosition) then (cameraPosition-head.Position).Magnitude else nil
 local focusDistance=if vector(cameraPosition) and vector(focusPosition) then (cameraPosition-focusPosition).Magnitude else nil
 return self.modeDetector:update(t,{
  forcedFirstPerson=self.player.CameraMode==Enum.CameraMode.LockFirstPerson,
  subjectIsLocal=humanoid~=nil and camera.CameraSubject==humanoid,
  headDistance=headDistance,focusDistance=focusDistance,
 })
end
function Session:_view(t)
 local camera=self.world.CurrentCamera
 assert(camera and type(camera.WorldToViewportPoint)=="function","CurrentCamera is unavailable")
 local size=camera.ViewportSize
 assert(size and finite(size.X) and finite(size.Y) and size.X>0 and size.Y>0,"Camera viewport is unavailable")
 local inset=self.services.GuiService:GetGuiInset()
 assert(inset and finite(inset.X) and finite(inset.Y),"GUI inset is unavailable")
 self.mode=self:_mode(t,camera)
 local mouse=self.services.UserInputService:GetMouseLocation()
 local reference=Selection.reference(self.mode,size,mouse,inset)
 assert(reference,"Selection reference is unavailable")
 return camera,inset,reference,if self.mode=="FirstPerson" then self.config.FirstPersonFOV else self.config.ThirdPersonFOV
end
function Session:_candidate(data,camera)
 local point,onScreen=camera:WorldToViewportPoint(data.part.Position)
 data.screenPosition=point
 data.onScreen=onScreen==true and vector(point) and point.Z>0
 data.visible=self:_visible(data)
 return data
end
function Session:_notify(message,subtitle,duration)
 if self.overlay then self.overlay:notify(message,self:_clock(),duration or self.config.NotificationDuration,subtitle) end
end
function Session:GetLockedTarget()
 return if self.locked and not self.destroyed then self.locked.player else nil
end
function Session:GetPrediction()
 return if not self.destroyed and self.comparisons then self.comparisons.active else nil
end
function Session:GetPredictedPosition()
 local record=self:GetPrediction()
 return record and record.position
end
function Session:LockTarget(player)
 if self.destroyed or not self.config.Enabled then return false,"Disabled" end
 if self.locked then return false,"Already Locked" end
 local t=self:_clock()
 local camera,inset,reference,fov=self:_view(t)
 local selected
 local candidates={}
 local evaluated,valid=0,0
 local rejections={}
 -- Enumerate players only on an explicit lock request, never each render.
 local players=if player then {player} else self.services.Players:GetPlayers()
 for _,p in players do
  if p~=self.player then
   evaluated+=1
   local data,reason=self:_targetData(p)
   if data then
    local candidate=self:_candidate(data,camera)
    if not candidate.onScreen then reason="offscreen or behind camera"
    elseif not candidate.visible then reason="occluded"
    elseif not Selection.within(candidate,reference,fov) then reason="outside FOV"
    else valid+=1;table.insert(candidates,candidate) end
   end
   if reason and self.config.DebugMode then table.insert(rejections,tostring(p.Name)..":"..reason) end
  end
 end
 selected=Selection.nearest(candidates,reference,fov)
 self.lastSelection={mode=self.mode,reference=reference,evaluated=evaluated,valid=valid,rejections=rejections,
  selected=selected and selected.player.Name or nil}
 if self.config.DebugMode then
  Runtime.trace(self.report,"Selection",if selected then "SELECTED" else "REJECT",
   "mode="..self.mode.." reference=("..reference.X..","..reference.Y..") evaluated="..evaluated.." valid="..valid
   .." rejections="..tostring(evaluated-valid).." ["..table.concat(rejections,"; ").."] selected="..tostring(self.lastSelection.selected))
 end
 if not selected then
  self:_notify("SEDWARE","No valid target")
  return false,"No valid visible target in FOV"
 end
 self.locked=selected
 self.prediction:reset()
 self.nextPing=nil
 self.comparisons=nil
 self.nextObservation=t
 self.lastError=nil
 local function lost()
  if self.locked==selected then self:UnlockTarget("Target Lost") end
 end
 connect(self.targetConnections,selected.humanoid.Died,lost)
 connect(self.targetConnections,selected.character.AncestryChanged,function()
  if not selected.character:IsDescendantOf(self.world) then lost() end
 end)
 connect(self.targetConnections,selected.part.AncestryChanged,function()
  if not selected.part:IsDescendantOf(selected.character) then lost() end
 end)
 if selected.player.CharacterRemoving then
  connect(self.targetConnections,selected.player.CharacterRemoving,function(character)
   if character==selected.character then lost() end
  end)
 end
 self:_step(t)
 if self.locked then self:_notify("Locked: "..tostring(selected.player.Name)) end
 return self.locked~=nil,if self.locked then "Locked" else "Target Lost"
end
function Session:UnlockTarget(reason)
 if not self.locked then return false end
 self.locked=nil
 disconnect(self.targetConnections)
 self.prediction:reset()
 self.comparisons=nil
 self.nextObservation=nil
 if self.overlay then self.overlay:hideDot() end
 if not self.destroyed then self:_notify(reason or "Unlocked") end
 return true
end
function Session:_ping(t)
 if self.nextPing and t<self.nextPing then return end
 self.nextPing=t+1/self.config.PingHz
 local ok,rtt=pcall(function() return self.player:GetNetworkPing() end)
 self.prediction:samplePing(if ok and finite(rtt) and rtt>=0 and rtt<=2 then rtt else nil,t)
end
function Session:_step(t)
 if self.destroyed then return end
 if not self.config.Enabled then self:destroy();return end
 local camera,inset,reference,fov=self:_view(t)
 self:_ping(t)
 if self.locked then
  local data=self:_targetData(self.locked.player)
  if not data or data.character~=self.locked.character or data.part~=self.locked.part then
   self:UnlockTarget("Target Lost")
  else
   if not self.config.TargetPersistence and not Selection.within(self:_candidate(data,camera),reference,fov) then
    self:UnlockTarget("Target Lost")
   else
    local point,onScreen=camera:WorldToViewportPoint(data.part.Position)
    self.overlay:setDot(point,onScreen==true and vector(point) and point.Z>0,inset)
    if not self.nextObservation or t+1e-7>=self.nextObservation then
     self.nextObservation=t+1/self.config.UpdateHz
     local state=tostring(data.humanoid:GetState())
     -- A local capture timestamp is NOT the server's replication-production time.
     -- Derive remote velocity from recent positions; no future truth is supplied.
     self.prediction:observe(t,data.part.Position,state)
    end
    self.comparisons=self.prediction:predictComparisons(self:_origin(),t)
   end
  end
 else self.overlay:hideDot() end
 self.overlay:step(t)
 if self.config.DebugMode and (not self.nextDebug or t>=self.nextDebug) then
  self.nextDebug=t+1
  local p=self:GetPrediction()
  print("[SEDWARE]", "target="..tostring(self:GetLockedTarget()),"mode="..tostring(self.mode),
   "pingRTTms="..tostring(p and p.rawPingMs),"smoothedRTTms="..tostring(p and p.smoothedPingMs),
   "X="..tostring(p and p.predictionX),"Y="..tostring(p and p.predictionY),
   "velocity="..tostring(p and p.velocity),"current="..tostring(p and p.currentPosition),
   "predicted="..tostring(p and p.position),"distance="..tostring(p and p.distanceStuds),
   "age="..tostring(p and p.ageSeconds),"errorStuds="..tostring(self.lastError),
   "status="..tostring(if p then p.status else "Ready | No target"))
 end
end
function Session:CreateShotAdapter(fire)
 assert(not self.destroyed,"Session is unloaded")
 for i=#self.adapters,1,-1 do if self.adapters[i].destroyed then table.remove(self.adapters,i) end end
 assert(#self.adapters<32,"Too many active shot adapters")
 local adapter=ShotAdapter.new({
  clock=function() return self:_clock() end,
  getSnapshot=function()
   if self.destroyed or not self.locked then return nil end
   local t=self:_clock()
   self:_step(t)
   if not self.locked or not self.comparisons or not self.comparisons.active then return nil end
   local p=self.comparisons.active
   return {targetUserId=self.locked.player.UserId,character=self.locked.character,part=self.locked.part,
    sampleTime=p.sampleTime,createdAt=t,active=p,manual=self.comparisons.manual,auto=self.comparisons.auto}
  end,
  isTargetValid=function(ticket)
   return not self.destroyed and self.locked~=nil and self.locked.player.UserId==ticket.targetUserId
    and self.locked.character==ticket.character and self.locked.part==ticket.part
    and self:IsValidTarget(self.locked.player)
  end,
  fire=fire,capacity=120,maxAge=1,
  onMeasurement=function(record)
   self.lastError=record.active and record.active.errorStuds
  end,
 })
 table.insert(self.adapters,adapter)
 return adapter
end
function Session:SetEnabled(enabled)
 assert(type(enabled)=="boolean","Enabled must be boolean")
 if not enabled then self:destroy();return true end
 return not self.destroyed
end
function Session:destroy()
 if self.destroyed then return end
 self.destroyed=true
 self.config.Enabled=false
 self.locked=nil;self.comparisons=nil
 disconnect(self.targetConnections)
 disconnect(self.connections)
 for _, adapter in self.adapters do pcall(function() adapter:destroy() end) end
 table.clear(self.adapters)
 if self.prediction then self.prediction:reset() end
 if self.overlay then self.overlay:destroy() end
 if self.owner then self.owner:Destroy() end
 if self.active then Runtime.trace(self.report,"Session","STOPPED","All session connections and owned graphics removed") end
 self.active=false
end
Session.Unload=Session.destroy

function Session.notifyFailure(report,message)
 if report and report.failureNotified then return end
 if report then report.failureNotified=true end
 Runtime.reportFailure(message)
 -- Independent Frame toast: no CanvasGroup, valid Config or server clock needed.
 local ok,result=xpcall(function() return Overlay.showFailure(report and report.playerGui,message) end,Runtime.traceback)
 Runtime.trace(report,"FailureNotification",if ok and result then "READY" else "FAIL",
  if ok and result then "Short error notification displayed" elseif ok then "PlayerGui unavailable; see console error" else result)
end
function Session.init(options,report)
 local config,message=Config.new(options)
 assert(config,message)
 report=report or Runtime.awaitReady(config)
 assert(report.ready,Runtime.errorMessage(report))
 local self=setmetatable({config=config,services=report.services,player=report.player,world=report.world,
  playerGui=report.playerGui,connections={},targetConnections={},adapters={},destroyed=false,report=report},Session)
 local old=report.playerGui:FindFirstChild(OWNER_NAME)
 if old and not old:IsA("BindableEvent") then error("Owner namespace is occupied by another object") end
 if not config.Enabled then
  if old then old:Fire() end
  self.destroyed=true
  Runtime.trace(report,"Session","DISABLED","Enabled=false; no GUI or input listeners created")
  return self
 end
 local stage="Prediction"
 local ok,err=xpcall(function()
  self.prediction=Prediction.new(config)
  self.modeDetector=ModeDetector.new(config)
  stage="Graphics"
  self.overlay=Overlay.new(self.playerGui,config)
  self.ui=self.overlay
  assert(self.overlay.gui.Parent==self.playerGui,"ScreenGui was not parented to PlayerGui")
  Runtime.trace(report,"Graphics","READY","DOT and notification objects created in PlayerGui")
  connect(self.connections,self.overlay.gui.Destroying,function() self:destroy() end)
  if typeof(script)=="Instance" and script.Destroying then
   connect(self.connections,script.Destroying,function() self:destroy() end)
  end
  if config.VisibilityCheck then
   self.rayParams=RaycastParams.new()
   self.rayParams.FilterType=Enum.RaycastFilterType.Exclude
   self.rayParams.IgnoreWater=true
  end
  self.owner=Instance.new("BindableEvent")
  self.owner.Name=OWNER_NAME
  connect(self.connections,self.owner.Event,function() self:destroy() end)
  connect(self.connections,self.services.Players.PlayerRemoving,function(player)
   if self.locked and self.locked.player==player then self:UnlockTarget("Target Lost") end
  end)
  stage="Input"
  self.inputConnection=connect(self.connections,self.services.UserInputService.InputBegan,function(input,processed)
   local succeeded,problem=xpcall(function()
   if input.KeyCode==self.config.LockKey then
    if self.config.DebugMode then Runtime.trace(report,"Input","KEY","key="..tostring(input.KeyCode).." detected; mode="..tostring(self.mode)) end
    if self.destroyed or processed or self.services.UserInputService:GetFocusedTextBox()~=nil then
     if self.config.DebugMode then
      Runtime.trace(report,"Selection","REJECT","mode="..tostring(self.mode).." reference=(not evaluated) evaluated=0 valid=0 rejections=1 selected=nil reason="
       ..(if processed then "Roblox processed input" else "TextBox focused or session inactive"))
     end
     return
    end
    if self.locked then
     if self.config.DebugMode then
      local _,_,reference=self:_view(self:_clock())
      Runtime.trace(report,"Selection","UNLOCKED","mode="..self.mode.." reference=("..reference.X..","..reference.Y
       ..") evaluated=0 valid=0 rejections=0 selected=nil reason=LockKey toggled existing lock")
     end
     self:UnlockTarget()
    else self:LockTarget() end
   end
   end,Runtime.traceback)
   if not succeeded then
    self:destroy()
    Session.notifyFailure(report,"InputBegan: "..tostring(problem))
   end
  end,"InputBegan")
  Runtime.trace(report,"Input","READY","InputBegan connected; LockKey="..tostring(config.LockKey))
  stage="View"
  -- Exercise view/clock/inset before announcing successful initialization.
  self:_step(self:_clock())
  stage="Render"
  self.renderConnection=connect(self.connections,self.services.RunService.RenderStepped,function()
   local succeeded,problem=xpcall(function() self:_step(self:_clock()) end,Runtime.traceback)
   if not succeeded then
    self:destroy()
    Session.notifyFailure(report,tostring(problem))
   elseif not self.firstRendered and not self.destroyed then
    self.firstRendered=true
    Runtime.trace(report,"Render","READY","First RenderStepped update completed; notification fade and observed DOT update are running")
   end
  end,"RenderStepped")
 end,Runtime.traceback)
 if not ok then report.failurePhase=stage;self:destroy();error(err,2) end
 -- Keep the previous running session until the replacement is fully initialized.
 local committed,problem=xpcall(function()
  -- Starting the toast at zero opacity can still fail; preserve the old owner
  -- until the replacement's final public-API writes have succeeded.
  if config.WelcomeNotification then
   local key=Config.keyName(config.LockKey)
   self:_notify("SEDWARE","Successfully Loaded | Press "..key.." to Lock",config.WelcomeDuration)
  end
  self.owner.Parent=self.playerGui
  if old then old:Fire() end
  assert(not self.destroyed and self.inputConnection.Connected and self.renderConnection.Connected,"Session became inactive during startup")
 end,Runtime.traceback)
 if not committed then report.failurePhase="Session";self:destroy();error(problem,2) end
 self.active=true
 Runtime.trace(report,"Session","ACTIVE","SEDWARE initialized; camera remains free")
 return self
end
return Session
