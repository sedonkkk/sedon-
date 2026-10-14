--!nonstrict
local Config=if script then require(script.Parent.Config) else require("./Config")
local UI=if script then require(script.Parent.UI) else require("./UI")
local NotificationSystem=if script then require(script.Parent.NotificationSystem) else require("./NotificationSystem")
local TargetSelector=if script then require(script.Parent.TargetSelector) else require("./TargetSelector")
local PredictionEngine=if script then require(script.Parent.PredictionEngine) else require("./PredictionEngine")
local CameraController=if script then require(script.Parent.CameraController) else require("./CameraController")
local Cleanup=if script then require(script.Parent.Cleanup) else require("./Cleanup")
local PlayerRegistry=if script then require(script.Parent.PlayerRegistry) else require("./PlayerRegistry")
local KeybindManager=if script then require(script.Parent.KeybindManager) else require("./KeybindManager")
local MovementAccess=if script then require(script.Parent.MovementAccess) else require("./MovementAccess")
local FlyController=if script then require(script.Parent.FlyController) else require("./FlyController")
local SpeedController=if script then require(script.Parent.SpeedController) else require("./SpeedController")
local MovementBridge=if script then require(script.Parent.MovementBridge) else require("./MovementBridge")
local ESPAccess=if script then require(script.Parent.ESPAccess) else require("./ESPAccess")
local ESPManager=if script then require(script.Parent.ESPManager) else require("./ESPManager")
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
function Session:GetTrackingDiagnostics()
 local d=self.controller:GetDiagnostics()
 d.target=self.locked and self.locked.player.Name;d.locked=self.locked~=nil
 d.trackingState=self.trackingState or "IDLE";d.reason=self.trackingReason;d.lastLoss=self.lastLoss
 d.pauseReason=self.pauseReason;d.prediction=self.predictionOutput
 d.observation=self.observation and table.clone(self.observation)
 return d
end
function Session:GetESPDiagnostics()
 local data=table.clone(self.esp.stats)
 data.loadedDataOnly=true;data.extendedAuthorized=ESPAccess.allowed(self.config,self.report)
 return data
end
function Session:_observe(now,position,state)
 local accepted,reason=self.prediction:observe(now,position,state)
 local previous=self.observation or {rejectedCount=0}
 self.observation={accepted=accepted==true,reason=reason,time=now,
  lastAcceptedAt=if accepted then now else previous.lastAcceptedAt,
  rejectedCount=previous.rejectedCount+(if accepted then 0 else 1),
  lastRejectedAt=if accepted then previous.lastRejectedAt else now,
  lastRejectedReason=if accepted then previous.lastRejectedReason else reason}
 if not accepted and self.config.DebugMode and (not self.nextObservationDiagnostic or now>=self.nextObservationDiagnostic) then
  self.nextObservationDiagnostic=now+1
  Runtime.trace(self.report,"CamObservation","REJECTED",reason or "Observation rejected")
 end
 return accepted,reason
end
function Session:_lose(code,detail)
 self.lastLoss={code=code,detail=detail,time=self:_clock(),target=self.locked and self.locked.player.Name}
 self:UnlockTarget("Target Lost")
 self.trackingState="LOST";self.trackingReason=code
 if not self.config.ReacquireOnLoss then self.manualReleased=true end
 Runtime.trace(self.report,"CamTarget",code,detail or code)
end
function Session:_bindTarget(data)
 self.targetCleanup:destroy();self.targetCleanup=Cleanup.new();self.locked=data
 local function lost(code)
  if self.locked==data then self:_lose(if type(code)=="string" then code else "TARGET_DEAD",code) end
 end
 self.targetCleanup:connect(data.humanoid.Died,lost,"Target.Died")
 self.targetCleanup:connect(data.character.AncestryChanged,function()
  if not data.character:IsDescendantOf(self.world) then lost("CHARACTER_REMOVED") end
 end)
 self.targetCleanup:connect(data.part.AncestryChanged,function()
  if not data.part:IsDescendantOf(data.character) then self.partGapSince=self:_clock();self:_pause("HIT_PART_UNAVAILABLE",self.partGapSince) end
 end)
 if data.player.CharacterRemoving then
  self.targetCleanup:connect(data.player.CharacterRemoving,function(character) if character==data.character then lost("CHARACTER_CHANGED") end end)
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
  self.trackingState="SEARCHING";self.trackingReason=reason
  if self.config.DebugMode and (not self.nextAcquisitionDebug or now>=self.nextAcquisitionDebug) then
   self.nextAcquisitionDebug=now+1;Runtime.trace(self.report,"Acquisition","SEARCHING",reason)
  end
  return false,reason
 end
 self.prediction:reset();self.controller:reset();self.predictionOutput=nil;self.observation=nil
 self.selector.lossSince=nil;self.nextRetention=nil
 self.nextObservation=nil;self.nextPing=nil
 self.partGapSince=nil;self.trackingState="TRACKING";self.trackingReason=nil
 self:_bindTarget(data)
 self:_ping(now)
 self:_observe(now,data.part.Position,tostring(data.humanoid:GetState()))
 self.nextObservation=now+1/self.config.UpdateHz
 self.predictionOutput=self.prediction:predict(self.selector:origin(),now)
 if self.predictionOutput then self.predictionOutput.captureTimeKnown=false;self.predictionOutput.ageSource="LocalReadTime" end
 self:_notify("Target Locked")
 Runtime.trace(self.report,"CamTarget","LOCKED",tostring(data.player.Name).." | "..data.actualHitPart)
 return true
end
function Session:UnlockTarget(reason)
 if not self.locked then return false end
 self.locked=nil;self.predictionOutput=nil;self.observation=nil
 self.trackingState=if self.config.Enabled then "IDLE" else "DISABLED";self.trackingReason=nil;self.pauseReason=nil
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
 if field=="MovementMode" and (self.config.Fly or self.config.Speed) then return false,"Disable Fly and Speed before changing movement route" end
 if (field=="Fly" or field=="Speed") and value==true and not MovementAccess.allowed(updated,self.report) then
  return false,if updated.MovementMode=="Server" then "Server component/authorization unavailable" else "Local movement requires a permitted test environment (Studio or explicit LocalMovementAllowed)"
 end
 if field=="Fly" then self.fly.error=nil end
 if field=="Speed" then self.speed.error=nil end
 if field=="Fly" and value==true then
  local started,reason=self.fly:start(self.registry.entries[self.player]);if not started then return false,reason end
 end
 if ((field=="ESPOcclusionMode" and value=="AlwaysOnTop") or (field=="ESPUnlimitedRange" and value==true) or (field=="ESP" and value==true and (updated.ESPOcclusionMode=="AlwaysOnTop" or updated.ESPUnlimitedRange))) and not ESPAccess.allowed(updated,self.report) then
  return false,"ESP AlwaysOnTop/UnlimitedRange requires an authorized context"
 end
 local priorEnabled=self.config.Enabled
 local priorPart=self.config.HitPart
 local accepted,problem=self.prediction:updateConfig(updated)
 if not accepted then return false,problem end
 for name,child in updated do self.config[name]=child end
 self.controller:setConfig(self.config)
 if self.ui then self.ui:setValue(field,self.config[field]) end
 if field=="Fly" and not value then self.fly:stop() end
 if field=="Speed" or field=="WalkSpeed" or field=="Fly" then self.speed:sync(self.registry.entries[self.player],self.config.Fly) end
 if field=="ESP" or field=="Hitboxes" or field=="Names" or field=="ESPTargetMode" or field=="ESPMaxDistance"
  or field=="ESPUpdateHz" or field=="ESPLowPerformanceMode" or field=="ESPOcclusionMode" or field=="ESPUnlimitedRange" or field=="ESPFarUpdateHz" then
  if self.esp.destroyed or field=="ESPOcclusionMode" then
   local applied=self.esp.selectedUsername;self.esp:destroy()
   self.esp=ESPManager.new(self.config,self.report,self.registry);self.esp.selectedUsername=applied
  end
  self.esp:refresh();local updatedESP,espError=self:_espUpdate(self:_clock())
  if not updatedESP then return false,"ESP API: "..tostring(espError) end
 end
 if field=="LogoAssetId" then self.ui:setLogo(value);self.notifications:setLogo(value) end
 if field=="ShowNotifications" then self.notifications.overlay.config.ShowNotifications=value end
 if field=="PredictionX" or field=="PredictionY" or field=="HitPart" or field:match("^Reference") then self.predictionOutput=nil end
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
  else self:UnlockTarget();self.controller:reset();self.trackingState="DISABLED";self.trackingReason=nil;self:_notify("Lock Disabled") end
 end
 return true
end
function Session:SetEnabled(value) return self:configure("Enabled",value) end
function Session:SetHitPart(value) return self:configure("HitPart",value) end
function Session:ApplyESPTarget()
 local accepted,reason=self.esp:applyTarget(self.config.ESPUsername)
 if accepted then self:configure("ESPTargetMode","Specific Player");return true end
 self:_notify(reason);return false,reason
end
function Session:ClearESPTarget()
 self:configure("ESPUsername","");self.esp:clearTarget();return true
end
function Session:_action(name,value)
 if name=="CaptureKey" then return self.keybinds and self.keybinds:capture(value)
 elseif name=="CancelCapture" then if self.keybinds then self.keybinds:cancelCapture() end
 elseif name=="ApplyTarget" then return self:ApplyESPTarget()
 elseif name=="ClearTarget" then return self:ClearESPTarget() end
end
function Session:_registryChanged(kind,entry)
 if self.destroyed then return end
 if self.esp then self.esp:changed(kind,entry) end
 if entry.player==self.player and (kind=="Died" or kind=="CharacterRemoving") then
  if self.fly then self.fly:stop() end;if self.speed then self.speed:stop() end
  if self.keybinds then self.keybinds:clear();self.keybinds:cancelCapture() end
  if self.ui then self.ui:resetDrag();self.ui:closeDropdown(true) end
 end
end
function Session:GetMovementDiagnostics()
 local entry=self.registry.entries[self.player];local ready=MovementAccess.ready(entry,self.world)
 local permitted=MovementAccess.allowed(self.config,self.report);local server=MovementAccess.server(self.config,self.report)
 local bridge=self.movementBridge;local result={mode=if server then "Server" else "Local",permitted=permitted,characterReady=ready==true}
 for _,field in {"Fly","Speed"} do
  local controller=if field=="Fly" then self.fly else self.speed
  local requested=self.config[field];local effective=false
  local requestedSpeed=if field=="Fly" then self.config.FlySpeed else self.config.WalkSpeed
  local measured,horizontal,vertical,serverMeasured,appliedSpeed,commandSpeed
  local wanted=false
  local state,reason="OFF","Not requested"
  if not requested then controller.probeSince=nil
  elseif not permitted then state="UNAVAILABLE";reason="No permitted local context or own server authorization"
  elseif field=="Speed" and requested and self.config.Fly then state="OFF";reason="Paused while Fly is requested"
  elseif requested and not ready then state="UNAVAILABLE";reason="Waiting for living, unanchored character"
  elseif requested then
   local root=entry.root;local velocity=root.AssemblyLinearVelocity
   local validVelocity=velocity and finite(velocity.X) and finite(velocity.Y) and finite(velocity.Z) and finite(velocity.Magnitude)
   if validVelocity then
    horizontal=math.sqrt(velocity.X^2+velocity.Z^2);vertical=velocity.Y
    measured=if field=="Fly" then velocity.Magnitude else horizontal
   end
   commandSpeed=if field=="Fly" then self.fly.velocity.Magnitude else self.config.WalkSpeed
   wanted=(if field=="Fly" then commandSpeed>self.config.MovementMinimumSpeed else entry.humanoid.MoveDirection and entry.humanoid.MoveDirection.Magnitude>0.1)==true
   local matching=validVelocity and (if field=="Fly" then wanted and velocity:Dot(self.fly.velocity)>0 else wanted and velocity:Dot(entry.humanoid.MoveDirection)>0)
   effective=(controller.active and measured and measured>=self.config.MovementMinimumSpeed and matching)==true
   if server then
    local applied=if field=="Fly" then bridge.serverFly else bridge.serverSpeed
    local serverHorizontal=self.player:GetAttribute("SEDWAREMeasuredHorizontalSpeed")
    local serverVertical=self.player:GetAttribute("SEDWAREMeasuredVerticalSpeed")
    if finite(serverHorizontal) and finite(serverVertical) then
     serverMeasured=if field=="Fly" then math.sqrt(serverHorizontal^2+serverVertical^2) else serverHorizontal
    end
    appliedSpeed=if field=="Speed" then self.player:GetAttribute("SEDWAREAppliedWalkSpeed") else (if applied then commandSpeed else nil)
    local overrideReason=field=="Speed" and self.player:GetAttribute("SEDWAREServerSpeedReason")
    if type(overrideReason)=="string" and overrideReason~="" then
     state="LIMITED";reason=overrideReason;effective=false
    elseif controller.limited or bridge.state=="SERVER_REJECTED" or bridge.state=="SERVER_TIMEOUT" then
     state="LIMITED";reason=bridge.reason or "Requested property changed externally";effective=false
    elseif not bridge.available then state="UNAVAILABLE";reason=bridge.reason or "Own server component unavailable";effective=false
    else
     effective=(effective and bridge.active and applied and serverMeasured and serverMeasured>=self.config.MovementMinimumSpeed)==true
     state=if effective then "SERVER ACTIVE" else "PENDING"
     reason=if effective then "Motion observed by client and own server; own request applied" else "Waiting for own server application, input or measured motion"
    end
   elseif controller.limited then state="LIMITED";reason="WalkSpeed changed externally; not overwritten";effective=false
   elseif effective then state="LOCAL ACTIVE";reason="Physical velocity observed locally; replication unverified"
   else
    state="PENDING";reason="Idle, waiting for input or physical confirmation"
   end
   if not server then appliedSpeed=if field=="Speed" then entry.humanoid.WalkSpeed else (controller.constraint and controller.constraint.VectorVelocity.Magnitude) end
   if wanted and not effective and state=="PENDING" then
    controller.probeSince=controller.probeSince or self:_clock()
    if self:_clock()-controller.probeSince>=self.config.MovementProbeSeconds then
     state="LIMITED";reason="Requested motion not observed; physical/environment cause unconfirmed"
    end
   else controller.probeSince=nil end
  end
  if controller.error then state="ERROR";reason=controller.error end
  result[field]={requested=requested,controllerActive=controller.active==true,effective=effective,state=state,reason=reason,
   requestedSpeed=requestedSpeed,commandSpeed=commandSpeed,appliedSpeed=appliedSpeed,
   observedSpeed=measured,observedHorizontalSpeed=horizontal,observedVerticalSpeed=vertical,
   serverObservedSpeed=serverMeasured,wantedInput=wanted}
 end
 return result
end
function Session:_movement(dt,now)
 self.movementBridge:step(now,if self.config.Fly then self.fly.velocity else nil)
 local route=if MovementAccess.server(self.config,self.report) then "Server" else "Local"
 if self.movementRoute and route~=self.movementRoute then
  self.fly:stop();self.speed:stop();self.fly.probeSince=nil;self.speed.probeSince=nil
 end
 self.movementRoute=route
 self.movementBridge:sync(self.registry.entries[self.player])
 if not self.config.Fly and not self.config.Speed and not self.fly.active and not self.speed.active then return end
 local entry=self.registry.entries[self.player]
 local ok,reason=pcall(function() self.fly:update(entry,self.world.CurrentCamera,dt,self.keybinds:movement()) end)
 if not ok then
  self.fly:stop();self.config.Fly=false;self.ui:setValue("Fly",false)
  self.fly.error=tostring(reason)
  Runtime.trace(self.report,"Fly","FAIL",reason);self:_notify("Fly unavailable | "..tostring(reason))
 end
 local speedOK,speedError=pcall(function() self.speed:sync(entry,self.config.Fly) end)
 if not speedOK then
  self.speed:stop();self.config.Speed=false;self.ui:setValue("Speed",false)
  self.speed.error=tostring(speedError)
  Runtime.trace(self.report,"Speed","FAIL",speedError);self:_notify("Speed unavailable | "..tostring(speedError))
 end
end
function Session:_espUpdate(now)
 local profiled=self.config.DebugMode and debug and type(debug.profilebegin)=="function" and type(debug.profileend)=="function"
 if profiled then debug.profilebegin("SEDWARE ESP") end
 local ok,reason=pcall(function() self.esp:update(now) end)
 if profiled then debug.profileend() end
 if not ok then
  self.esp:destroy();self.config.ESP=false;self.ui:setValue("ESP",false)
  Runtime.trace(self.report,"ESP","FAIL",reason);self:_notify("ESP unavailable | "..tostring(reason))
 end
 return ok,reason
end
function Session:_ping(now)
 if self.nextPing and now<self.nextPing then return end
 self.nextPing=now+1/self.config.PingHz
 local measured,rtt=pcall(function() return self.player:GetNetworkPing() end)
 self.prediction:samplePing(if measured and finite(rtt) and rtt>=0 and rtt<=2 then rtt else nil,now)
end
function Session:_pause(reason,now)
 self.trackingState="PAUSED";self.trackingReason=reason
 self.controller:reset()
 if reason~=self.pauseReason then Runtime.trace(self.report,"CamTracking","PAUSED",reason) end
 self.pauseReason=reason
end
function Session:_cameraDiagnostic(now)
 if not self.config.CameraDebugMode or (self.nextCameraDiagnostic and now<self.nextCameraDiagnostic) then return end
 self.nextCameraDiagnostic=now+self.config.CameraDebugInterval
 local data=self.controller:GetDiagnostics()
 Runtime.trace(self.report,"CamCamera",data.state,string.format(
  "yaw=%.3f pitch=%.3f roll=%.6f targetAngle=%.3f deltaTime=%.6f angularError=%.3f yawError=%s pitchError=%s pitchRate=%s pitchAccelerationApplied=%s safety=%s conflict=%s overshootReference=%s",
  data.yaw,data.pitch,data.roll,data.targetAngle,data.deltaTime,data.angularError,tostring(data.yawError),tostring(data.pitchError),
  tostring(data.pitchRate),tostring(data.accelerationApplied),tostring(data.safetyState),tostring(data.constraintConflict),tostring(data.overshootReference)))
end
function Session:_track(dt,now)
 if not self.config.Enabled then return end
 local camera=self.world.CurrentCamera
 local size=camera and camera.ViewportSize
 if not camera or not size or not finite(size.X) or not finite(size.Y) or size.X<=0 or size.Y<=0 then
  self:_pause("CurrentCamera or viewport temporarily unavailable",now);return
 end
 self:_ping(now)
 if not self.locked and not self.manualReleased and now>=(self.nextAcquisition or 0) then self:LockTarget() end
 if not self.locked then return end
 local data,reason=self.selector:validateLocked(self.locked)
 if not data then
  if reason=="camera origin unavailable" then
   self:_pause("CAMERA_ORIGIN_UNAVAILABLE",now);return
  elseif reason=="Hit Part unavailable" then
   self.partGapSince=self.partGapSince or now
   local replacement=self.selector:resolve(self.locked.player)
   if replacement and replacement.character==self.locked.character then
    self:_bindTarget(replacement);self.prediction:reset();self.controller:reset();self.nextObservation=nil
    self.partGapSince=nil;data=replacement
   elseif now-self.partGapSince<self.config.TargetPartGraceSeconds then self:_pause("HIT_PART_UNAVAILABLE",now);return
   else self:_lose("HIT_PART_UNAVAILABLE",reason);return end
  else
   local code=if reason=="target exceeds MaxDistance" then "OUT_OF_RANGE" elseif reason=="target is dead/humanoid replaced" then "TARGET_DEAD_OR_HUMANOID_CHANGED" else "CHARACTER_UNAVAILABLE"
   self:_lose(code,reason);return
  end
 end
 if self.config.SmartSelection and (not self.nextRetention or now>=self.nextRetention) then
  self.nextRetention=now+1/self.config.TargetVisibilityHz
  local retained,loss=self.selector:retain(data,now)
  if retained==false then self:_lose(if loss=="occluded beyond grace" then "OCCLUDED" else "OFFSCREEN_OR_RELEASE_RADIUS",loss);return end
  self.retentionPaused=retained==nil
 end
 if self.config.SmartSelection and self.retentionPaused then self:_pause("Target temporarily outside visible bounds",now);return end
 if not self.nextObservation or now+1e-7>=self.nextObservation then
  self.nextObservation=now+1/self.config.UpdateHz
  self:_observe(now,data.part.Position,tostring(data.humanoid:GetState()))
 end
 self.predictionOutput=self.prediction:predict(camera.CFrame.Position,now)
 if self.predictionOutput then self.predictionOutput.captureTimeKnown=false;self.predictionOutput.ageSource="LocalReadTime" end
 if not self.predictionOutput then self:_pause("PREDICTION_UNAVAILABLE_OR_STALE",now);return end
 if self.config.RespectScriptableCamera and camera.CameraType==Enum.CameraType.Scriptable then
  self:_pause("Scriptable camera active; preserving its controller",now);return
 end
 if not finite(dt) or dt<=0 then return end
 local moved,message=self.controller:update(camera,self.predictionOutput.position,dt,self.predictionOutput)
 self:_cameraDiagnostic(now)
 if not moved then self:_pause("CONTROLLER_ERROR | "..tostring(message),now);return end
 if self.pauseReason then Runtime.trace(self.report,"CamTracking","RESUMED","Predicted Hit Part tracking resumed") end
 self.pauseReason=nil;self.trackingState="TRACKING";self.trackingReason=nil
end
function Session:_step(dt)
 if self.destroyed then return end
 local now=self:_clock()
 local started=os.clock()
 self.ui:step(now);self.notifications:step(now)
 self:_track(dt,now);self:_movement(dt,now);self:_espUpdate(now)
 if self.config.ShowFOV then self.ui:updateFOV(self.selector:reference(now),self.config.Radius) else self.ui:updateFOV(nil,0) end
 self.updateSeconds=os.clock()-started
 if not self.nextStatus or now>=self.nextStatus then
  self.nextStatus=now+0.5
  local movementReport=self:GetMovementDiagnostics()
  local allowed=movementReport.permitted
  local bridge=self.movementBridge
  local movement="Fly "..movementReport.Fly.state.." / Speed "..movementReport.Speed.state
  local stats=self.esp.stats
  local esp=if not self.config.ESP then "OFF | Enable ESP + Hitboxes or Names"
   elseif not self.config.Hitboxes and not self.config.Names then "Choose Hitboxes or Names to show indicators"
   else string.format("%s %s | %d visible / %d evaluated",
    if stats.mode=="AlwaysOnTop" then "Always On Top" else "Visible Only",
    if stats.unlimitedRange then "loaded" else tostring(stats.maxDistance),stats.visible,stats.considered)
  self.ui:setStatus(movement,esp,allowed,movementReport)
  if self.config.DebugMode then
   Runtime.trace(self.report,"Movement","STATUS",movement.." | mode="..movementReport.mode.." | "..movementReport.Fly.reason.." | "..movementReport.Speed.reason)
   for _,field in {"Fly","Speed"} do
    local m=movementReport[field]
    Runtime.trace(self.report,"Movement","MEASURE",string.format("%s requestedSpeed=%s command=%s applied=%s observed=%s serverObserved=%s input=%s controllerActive=%s effective=%s",
     field,tostring(m.requestedSpeed),tostring(m.commandSpeed),tostring(m.appliedSpeed),tostring(m.observedSpeed),tostring(m.serverObservedSpeed),tostring(m.wantedInput),tostring(m.controllerActive),tostring(m.effective)))
   end
   Runtime.trace(self.report,"ESP","DIAGNOSTIC",string.format("registered=%d evaluated=%d range=%d screen=%d occluded=%d notReady=%d far=%d offscreen=%d visible=%d active=%d created=%d raycasts=%d ms=%.4f maxMs=%.4f",
    stats.registered,stats.considered,stats.inRange,stats.onScreen,stats.occluded,stats.notReady,stats.outOfRange,stats.offscreen,stats.visible,stats.active,stats.created,stats.raycasts,stats.lastSeconds*1000,stats.maxSeconds*1000))
   Runtime.trace(self.report,"ESP","MODE",string.format("mode=%s range=%s loadedDataOnly=true invalidRoot=%s invalidHead=%s",
    tostring(stats.mode),if stats.unlimitedRange then "Unlimited" else tostring(stats.maxDistance),tostring(stats.invalidRoot),tostring(stats.invalidHead)))
   local p=self.predictionOutput;local d=self.controller.diagnostics
   Runtime.trace(self.report,"Tracking","DIAGNOSTIC",string.format("target=%s angularError=%.3f scaleX=%.2f scaleY=%.2f horizonX=%.6f horizonY=%.6f smoothness=%.3f mode=%s fps=%.1f pingMs=%s smoothedPingMs=%s localReadAge=%s captureTime=unknown observationDelay=unknown updateMs=%.4f",
    self.locked and self.locked.player.Name or "none",d.angularError,self.config.PredictionX,self.config.PredictionY,
    p and p.predictionX or 0,p and p.predictionY or 0,self.config.Smoothness,self.config.TrackingMode,
    if finite(dt) and dt>0 then 1/dt else 0,tostring(p and p.rawPingMs),tostring(p and p.smoothedPingMs),tostring(p and p.ageSeconds),self.updateSeconds*1000))
   Runtime.trace(self.report,"Tracking","STATE",string.format("state=%s reason=%s lastLoss=%s phase=%s hitPart=%s verticalVelocity=%s yawError=%s pitchError=%s horizonXUsed=%s horizonYUsed=%s",
    tostring(self.trackingState),tostring(self.trackingReason),self.lastLoss and self.lastLoss.code or "none",p and p.movementPhase or "unknown",self.config.HitPart,
    tostring(p and p.verticalVelocityUsed),tostring(d.yawError),tostring(d.pitchError),tostring(p and p.horizontalHorizonUsed),tostring(p and p.verticalHorizonUsed)))
   local o=self.observation
   Runtime.trace(self.report,"Tracking","QUALITY",string.format("observeAccepted=%s rejection=%s rejectedCount=%s verticalAnomaly=%s anomalyReason=%s rawYVelocity=%s pitchRate=%s appliedAcceleration=%s safety=%s conflict=%s overshootReference=%s pitchOvershoot=%s",
    tostring(o and o.accepted),tostring(o and o.reason),tostring(o and o.rejectedCount),tostring(p and p.verticalAnomaly),tostring(p and p.verticalAnomalyReason),
    tostring(p and p.verticalRawVelocity),tostring(d.pitchRate),tostring(d.accelerationApplied),tostring(d.safetyState),tostring(d.constraintConflict),tostring(d.overshootReference),tostring(d.pitchOvershootDegrees)))
  end
 end
end
function Session:destroy()
 if self.destroyed then return end
 self.destroyed=true;self.config.Enabled=false;self.locked=nil;self.predictionOutput=nil
 self.targetCleanup:destroy();self.cleanup:destroy()
 if self.keybinds then self.keybinds:destroy() end
 if self.movementBridge then self.movementBridge:destroy() end
 if self.fly then self.fly:destroy() end;if self.speed then self.speed:destroy() end
 if self.esp then self.esp:destroy() end;if self.registry then self.registry:destroy() end
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
  stage="Registry"
  self.registry=PlayerRegistry.new(self.services.Players,function(kind,entry) self:_registryChanged(kind,entry) end)
  report.registry=self.registry
  self.prediction=PredictionEngine.new(config);self.controller=CameraController.new(config);self.selector=TargetSelector.new(config,report)
  assert(not (config.ESP and (config.ESPOcclusionMode=="AlwaysOnTop" or config.ESPUnlimitedRange)) or ESPAccess.allowed(config,report),"ESP mode requires authorization")
  self.movementBridge=MovementBridge.new(config,report);report.movementBridge=self.movementBridge
  self.movementRoute=if MovementAccess.server(config,report) then "Server" else "Local"
  self.fly=FlyController.new(config,report);self.speed=SpeedController.new(config,report);self.esp=ESPManager.new(config,report,self.registry)
  if (config.Fly or config.Speed) and not MovementAccess.allowed(config,report) then Runtime.trace(report,"Movement","UNAVAILABLE","Requested movement has no permitted local context or own server authorization") end
  stage="Graphics"
  self.notifications=NotificationSystem.new(report.playerGui,config)
  self.ui=UI.new(report.playerGui,config,function(field,value) return self:configure(field,value) end,
   function(reason,field)
    local descriptor=field and Config.fields[field]
    local prefix=if descriptor and descriptor.section=="MOVEMENT" then descriptor.label.." | " else "Invalid value | "
    self:_notify(prefix..tostring(reason))
   end,function(name,value) return self:_action(name,value) end,self.player)
  self.gui=self.ui.gui
  assert(self.gui.Parent==report.playerGui and self.notifications.gui.Parent==report.playerGui,"Cam Lock interface failed to attach")
  self.cleanup:connect(self.gui.Destroying,function() self:destroy() end)
  self.cleanup:connect(self.notifications.gui.Destroying,function() self:destroy() end)
  if typeof(script)=="Instance" and script.Destroying then self.cleanup:connect(script.Destroying,function() self:destroy() end) end
  self.owner=Instance.new("BindableEvent");self.owner.Name=OWNER;self.owner:SetAttribute("Generation",previous+1)
  self.cleanup:connect(self.owner.Event,function() self:destroy() end)
  Runtime.trace(report,"CamGraphics","READY","Pink Edition MAIN/MISC, popup layer and prepared original-logo asset created")
  if not self.ui.animations.service then Runtime.trace(report,"UIAnimations","UNAVAILABLE","TweenService missing; GUI state applies immediately") end
  stage="Input"
  self.keybinds=KeybindManager.new(config,self.services.UserInputService,{
   capture=function(field,active) self.ui:setCapture(field,active) end,
   change=function(field,value) return self:configure(field,value) end,
   notice=function(reason) self:_notify("Invalid key | "..tostring(reason)) end,
   toggle=function(field) local changed,reason=self:configure(field,not self.config[field]);if not changed then self:_notify(reason) end end,
   lock=function()
    if self.destroyed or not self.config.Enabled then return end
    local handled,errorMessage=xpcall(function()
     if self.locked then self.manualReleased=true;self:UnlockTarget("Target Lost") else self:LockTarget() end
    end,Runtime.traceback)
    if not handled then self:destroy();Session.notifyFailure(report,errorMessage) end
   end,
  })
  self.cleanup:connect(self.services.Players.PlayerRemoving,function(player) if self.locked and self.locked.player==player then self:_lose("PLAYER_LEFT",tostring(player.Name).." left") end end)
  stage="Render"
  self.cleanup:add(function() run:UnbindFromRenderStep(self.bindName) end)
  run:BindToRenderStep(self.bindName,priority+1,function(dt)
   local advanced,renderError=xpcall(function() self:_step(dt) end,Runtime.traceback)
   if not advanced then self:destroy();Session.notifyFailure(report,"Cam render: "..tostring(renderError))
   elseif not self.firstRendered then self.firstRendered=true;Runtime.trace(report,"CamRender","READY","First ordered RenderStepped update completed") end
  end)
  Runtime.trace(report,"CamRender","BOUND","Camera+1 RenderStepped binding registered; awaiting first frame")
  if config.WelcomeNotification then self:_notify("Successfully Loaded",config.WelcomeDuration) end
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
