--!nonstrict
local Config=if script then require(script.Parent.Config) else require("./Config")
local UI=if script then require(script.Parent.UI) else require("./UI")
local NotificationSystem=if script then require(script.Parent.NotificationSystem) else require("./NotificationSystem")
local TargetSelector=if script then require(script.Parent.TargetSelector) else require("./TargetSelector")
local PredictionEngine=if script then require(script.Parent.PredictionEngine) else require("./PredictionEngine")
local CameraController=if script then require(script.Parent.CameraController) else require("./CameraController")
local Cleanup=if script then require(script.Parent.Cleanup) else require("./Cleanup")
local Runtime=if script then require(script.Parent.Parent.pink.Runtime) else require("../pink/Runtime")
local Overlay=if script then require(script.Parent.Parent.pink.Overlay) else require("../pink/Overlay")
local Session={}
Session.__index=Session
local OWNER="SedwareCamLock_Owner_v1"
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
function Session:_clock()
 local value=self.world:GetServerTimeNow();assert(finite(value),"Invalid Cam Lock clock");return value
end
function Session:_notify(message,duration)
 if self.notifications and not self.destroyed then self.notifications:notify(message,self:_clock(),duration or self.config.NotificationDuration) end
end
function Session:_bindTarget(data)
 self.targetCleanup:destroy();self.targetCleanup=Cleanup.new();self.locked=data
 local function lost()
  if self.locked==data then self:UnlockTarget("Target Lost") end
 end
 self.targetCleanup:connect(data.humanoid.Died,lost,"Target.Died")
 self.targetCleanup:connect(data.character.AncestryChanged,function()
  if not data.character:IsDescendantOf(self.world) then lost() end
 end)
 self.targetCleanup:connect(data.part.AncestryChanged,function()
  if not data.part:IsDescendantOf(data.character) then lost() end
 end)
 if data.player.CharacterRemoving then
  self.targetCleanup:connect(data.player.CharacterRemoving,function(character) if character==data.character then lost() end end)
 end
end
function Session:LockTarget(player)
 if self.destroyed or not self.config.Enabled then return false,"Cam Lock is disabled" end
 if self.locked then return false,"Target is already locked" end
 self.manualReleased=false
 local now=self:_clock()
 self.nextAcquisition=now+self.config.AcquisitionInterval
 local data,reason=self.selector:acquire(player)
 self.lastSelection=self.selector.lastSelection
 if not data then
  if not self.nextNoTargetNotice or now>=self.nextNoTargetNotice then
   self.nextNoTargetNotice=now+2;self:_notify(reason)
  end
  return false,reason
 end
 self.prediction:reset();self.controller:reset();self.predictionOutput=nil
 self.nextObservation=nil;self.nextPing=nil
 self:_bindTarget(data)
 self:_ping(now)
 self.prediction:observe(now,data.part.Position,tostring(data.humanoid:GetState()))
 self.nextObservation=now+1/self.config.UpdateHz
 self.predictionOutput=self.prediction:predict(self.selector:origin(),now)
 self:_notify("Target Locked")
 Runtime.trace(self.report,"CamTarget","LOCKED",tostring(data.player.Name).." | "..data.actualHitPart)
 return true
end
function Session:UnlockTarget(reason)
 if not self.locked then return false end
 self.locked=nil;self.predictionOutput=nil
 self.targetCleanup:destroy();self.targetCleanup=Cleanup.new()
 self.prediction:reset();self.controller:reset();self.nextObservation=nil;self.nextPing=nil
 self.nextAcquisition=self:_clock()+self.config.AcquisitionInterval
 if reason then self:_notify(reason) end
 return true
end
function Session:GetLockedTarget() return if self.locked and not self.destroyed then self.locked.player else nil end
function Session:GetPrediction() return if not self.destroyed then self.predictionOutput else nil end
function Session:GetPredictedPosition() local prediction=self:GetPrediction();return prediction and prediction.position end
function Session:configure(field,value)
 if self.destroyed then return false,"Session is unloaded" end
 local updated,message=Config.update(self.config,field,value)
 if not updated then return false,message end
 local priorEnabled=self.config.Enabled
 local priorPart=self.config.HitPart
 local accepted,problem=self.prediction:updateConfig(updated)
 if not accepted then return false,problem end
 for name,child in updated do self.config[name]=child end
 self.controller:setConfig(self.config)
 if self.ui then self.ui:setValue(field,self.config[field]) end
 self.predictionOutput=nil
 if priorPart~=self.config.HitPart then
  self.controller:reset();self.nextObservation=nil
  if self.locked then
   local data,reason=self.selector:resolve(self.locked.player)
   if data and data.character==self.locked.character then self:_bindTarget(data)
   else self:UnlockTarget("Target Lost");Runtime.trace(self.report,"HitPart","REJECT",reason) end
  end
 end
 if priorEnabled~=self.config.Enabled then
  if self.config.Enabled then self.manualReleased=false;self:_notify("Lock Enabled");self.nextAcquisition=0;self:LockTarget()
  else self:UnlockTarget();self.controller:reset();self:_notify("Lock Disabled") end
 end
 return true
end
function Session:SetEnabled(value) return self:configure("Enabled",value) end
function Session:SetHitPart(value) return self:configure("HitPart",value) end
function Session:_ping(now)
 if self.nextPing and now<self.nextPing then return end
 self.nextPing=now+1/self.config.PingHz
 local measured,rtt=pcall(function() return self.player:GetNetworkPing() end)
 self.prediction:samplePing(if measured and finite(rtt) and rtt>=0 and rtt<=2 then rtt else nil,now)
end
function Session:_pause(reason,now)
 self.controller:reset()
 if reason~=self.pauseReason then Runtime.trace(self.report,"CamTracking","PAUSED",reason) end
 self.pauseReason=reason
end
function Session:_cameraDiagnostic(now)
 if not self.config.CameraDebugMode or (self.nextCameraDiagnostic and now<self.nextCameraDiagnostic) then return end
 self.nextCameraDiagnostic=now+self.config.CameraDebugInterval
 local data=self.controller:GetDiagnostics()
 Runtime.trace(self.report,"CamCamera",data.state,string.format(
  "yaw=%.3f pitch=%.3f roll=%.6f targetAngle=%.3f deltaTime=%.6f angularError=%.3f",
  data.yaw,data.pitch,data.roll,data.targetAngle,data.deltaTime,data.angularError))
end
function Session:_step(dt)
 if self.destroyed then return end
 local now=self:_clock()
 self.ui:step();self.notifications:step(now)
 if not self.config.Enabled then return end
 local camera=self.world.CurrentCamera
 local size=camera and camera.ViewportSize
 if not camera or not size or not finite(size.X) or not finite(size.Y) or size.X<=0 or size.Y<=0 then
  self:_pause("CurrentCamera or viewport temporarily unavailable",now);return
 end
 self:_ping(now)
 if not self.locked and not self.manualReleased and now>=(self.nextAcquisition or 0) then self:LockTarget() end
 if not self.locked then return end
 local data,reason=self.selector:resolve(self.locked.player)
 if not data or data.character~=self.locked.character or data.part~=self.locked.part then
  self:UnlockTarget("Target Lost");Runtime.trace(self.report,"CamTarget","LOST",reason or "character/part changed");return
 end
 if not self.nextObservation or now+1e-7>=self.nextObservation then
  self.nextObservation=now+1/self.config.UpdateHz
  self.prediction:observe(now,data.part.Position,tostring(data.humanoid:GetState()))
 end
 self.predictionOutput=self.prediction:predict(camera.CFrame.Position,now)
 if not self.predictionOutput then self:_pause("Prediction unavailable or observation stale",now);return end
 if self.config.RespectScriptableCamera and camera.CameraType==Enum.CameraType.Scriptable then
  self:_pause("Scriptable camera active; preserving its controller",now);return
 end
 if not finite(dt) or dt<=0 then return end
 local moved,message=self.controller:update(camera,self.predictionOutput.position,dt)
 self:_cameraDiagnostic(now)
 if not moved then self:_pause(message,now);return end
 if self.pauseReason then Runtime.trace(self.report,"CamTracking","RESUMED","Predicted Hit Part tracking resumed") end
 self.pauseReason=nil
end
function Session:destroy()
 if self.destroyed then return end
 self.destroyed=true;self.config.Enabled=false;self.locked=nil;self.predictionOutput=nil
 self.targetCleanup:destroy();self.cleanup:destroy()
 if self.controller then self.controller:destroy() end
 if self.ui then self.ui:destroy() end
 if self.notifications then self.notifications:destroy() end
 if self.owner then pcall(function() self.owner:Destroy() end) end
 self.active=false
 self.report.ready=false;self.report.sessionActive=false
 Runtime.trace(self.report,"CamSession","STOPPED","Camera binding, UI and all owned signals removed")
end
Session.Unload=Session.destroy
function Session.notifyFailure(report,message)
 Runtime.reportFailure(message)
 local shown,problem=pcall(Overlay.showFailure,report and report.playerGui,message)
 if not shown then Runtime.trace(report,"CamFailureNotification","FAIL",problem) end
end
function Session.init(options,report)
 local config,message=Config.new(options);assert(config,message)
 report=report or Runtime.awaitReady(config)
 assert(report.ready,Runtime.errorMessage(report))
 local run=report.services.RunService
 assert(type(run.BindToRenderStep)=="function" and type(run.UnbindFromRenderStep)=="function","Cam Lock requires BindToRenderStep and UnbindFromRenderStep")
 assert(CFrame and type(CFrame.lookAt)=="function" and type(CFrame.new)=="function","Cam Lock requires native CFrame.lookAt/new")
 assert(type(CFrame.fromMatrix)=="function","Cam Lock requires native CFrame.fromMatrix for level yaw/pitch orientation")
 local priority=Enum.RenderPriority.Camera.Value
 assert(finite(priority),"Roblox camera render priority unavailable")
 local old=report.playerGui:FindFirstChild(OWNER,true)
 assert(not old or old:IsA("BindableEvent"),"Cam Lock owner namespace occupied")
 local previous=if old then old:GetAttribute("Generation") else 0
 previous=if finite(previous) and previous>=0 and previous%1==0 then previous else 0
 local self=setmetatable({config=config,report=report,player=report.player,world=report.world,services=report.services,
  cleanup=Cleanup.new(),targetCleanup=Cleanup.new(),destroyed=false,active=false,
  bindName="SEDWARE_CAM_LOCK_"..tostring(previous+1)},Session)
 local stage="Prediction"
 local initialized,problem=xpcall(function()
  self.prediction=PredictionEngine.new(config);self.controller=CameraController.new(config);self.selector=TargetSelector.new(config,report)
  stage="Graphics"
  self.notifications=NotificationSystem.new(report.playerGui,config)
  self.ui=UI.new(report.playerGui,config,function(field,value) return self:configure(field,value) end,
   function(reason) self:_notify("Invalid value | "..tostring(reason)) end)
  self.gui=self.ui.gui
  assert(self.gui.Parent==report.playerGui and self.notifications.gui.Parent==report.playerGui,"Cam Lock interface failed to attach")
  self.cleanup:connect(self.gui.Destroying,function() self:destroy() end)
  self.cleanup:connect(self.notifications.gui.Destroying,function() self:destroy() end)
  if typeof(script)=="Instance" and script.Destroying then self.cleanup:connect(script.Destroying,function() self:destroy() end) end
  self.owner=Instance.new("BindableEvent");self.owner.Name=OWNER;self.owner:SetAttribute("Generation",previous+1)
  self.cleanup:connect(self.owner.Event,function() self:destroy() end)
  Runtime.trace(report,"CamGraphics","READY","Compact seven-control interface and Sedware S fallback created")
  stage="Input"
  self.cleanup:connect(self.services.UserInputService.InputBegan,function(input,processed)
   if self.destroyed or processed or not self.config.Enabled or self.services.UserInputService:GetFocusedTextBox() then return end
   if input.KeyCode==self.config.LockKey then
    local handled,errorMessage=xpcall(function()
     if self.locked then self.manualReleased=true;self:UnlockTarget("Target Lost") else self:LockTarget() end
    end,Runtime.traceback)
    if not handled then self:destroy();Session.notifyFailure(report,errorMessage) end
   end
  end,"CamLock.InputBegan")
  self.cleanup:connect(self.services.Players.PlayerRemoving,function(player) if self.locked and self.locked.player==player then self:UnlockTarget("Target Lost") end end)
  stage="Render"
  self.cleanup:add(function() run:UnbindFromRenderStep(self.bindName) end)
  run:BindToRenderStep(self.bindName,priority+1,function(dt)
   local advanced,renderError=xpcall(function() self:_step(dt) end,Runtime.traceback)
   if not advanced then self:destroy();Session.notifyFailure(report,"Cam render: "..tostring(renderError))
   elseif not self.firstRendered then self.firstRendered=true;Runtime.trace(report,"CamRender","READY","First ordered RenderStepped update completed") end
  end)
  Runtime.trace(report,"CamRender","BOUND","Camera+1 RenderStepped binding registered; awaiting first frame")
  if config.WelcomeNotification then self:_notify("Cam Lock Loaded",config.WelcomeDuration) end
 end,Runtime.traceback)
 if not initialized then report.failurePhase=stage;self:destroy();error(problem,2) end
 local committed,commitError=xpcall(function()
  self.owner.Parent=self.gui
  if self.config.Enabled then self:LockTarget() end
  if old then old:Fire() end
  assert(not self.destroyed and self.gui.Parent,"Cam Lock session inactive during owner handoff")
  self.active=true
  self.report.sessionActive=true
 end,Runtime.traceback)
 if not committed then report.failurePhase="CamCommit";self:destroy();error(commitError,2) end
 Runtime.trace(report,"CamSession","ACTIVE","UI ready; camera control Enabled="..tostring(config.Enabled))
 return self
end
return Session
