--!nonstrict
-- Actual standalone Session/UI integration with explicit API/event doubles.
-- Raw positions and velocity observations are fixtures, not Roblox physics.
return function(reloadBundle)
 local Mock=require("./CamV2Mock")
 local tests,checks,failures=0,0,0
 local function check(value,message)
  checks+=1;assert(value,message or ("V3.2 Session assertion at line "..tostring(debug.info(2,"l"))))
 end
 local function near(value,expected,tolerance)
  check(type(value)=="number" and value==value and math.abs(value-expected)<=(tolerance or 1e-8),
   tostring(value).." ~= "..tostring(expected))
 end
 local function test(name,body)
  tests+=1;local m=Mock.new();local a=reloadBundle(m.env)
  local ok,problem=pcall(body,m,a)
  if not ok then failures+=1;print("FAIL V3.2 Session "..name..": "..tostring(problem)) end
  a.Unload()
  check(m:countConnections()==0,"connection survived unload")
  check(m:countRenderBindings()==0,"render binding survived unload")
  check(m:liveInstances("LinearVelocity")==0,"LinearVelocity survived unload")
  check(m:liveInstances("AlignOrientation")==0,"AlignOrientation survived unload")
  check(m:liveInstances("Highlight")==0,"Highlight survived unload")
  check(m.tweens.active==0,"tween survived unload")
 end
 local function choose(ui,field,value)
  ui.controls[field].Activated:Fire()
  check(ui.popupField==field and ui.dropdown.Visible,"real dropdown did not open")
  local index=table.find(ui.popupOptions,value)
  check(index~=nil,"dropdown is missing configured option")
  check(ui.popupButtons[index].Active,"configured option cannot be selected")
  ui.popupButtons[index].Activated:Fire()
  check(ui.popupField==nil,"dropdown did not close after selection")
 end
 local function edit(ui,field,value)
  check(ui.controls[field]:IsA("TextBox"),"numeric control is not an editable TextBox")
  ui.controls[field].Text=tostring(value);ui.controls[field].FocusLost:Fire(true)
 end
 local function engine(a,overrides)
  return a.Modules.PredictionEngine.new(assert(a.Modules.Config.new(overrides or {})))
 end
 test("MISC route dropdown exposes Auto Local Server without losing C target",function(m,a)
  local target=m:addPlayer("PersistentMISC",m.env.Vector3.new(0,0,-50))
  local s=a.init({Enabled=true,WelcomeNotification=false});local ui=s.ui
  ui.tabButtons.MISC.Activated:Fire();check(ui.tab=="MISC")
  check(ui.title.Text=="SEDWARE V3.2" and ui.version.Text=="v3.2")
  for _,value in {"Local","Server","Auto"} do
   choose(ui,"MovementMode",value);check(s.config.MovementMode==value)
   check(s:GetLockedTarget()==target and s.config.Enabled,"changing inactive movement route discarded target")
  end
  check(#a.Modules.Config.fields.MovementMode.options==3)
  check(ui.miscScroll.CanvasSize.Y.Offset>ui.miscScroll.Size.Y.Offset,"extended MISC controls lost scrolling")
 end)
 test("Smoothness textbox affects elapsed tracking while default pitch safety bounds every applied frame",function(m,a)
  local V,F=m.env.Vector3,m.env.CFrame
  local target=m:addPlayer("DefaultGuardSmoothness",V.new(30,0,-50));local errors={}
  for _,smoothness in {.9,.1} do
   a.Unload();local initial=F.new(V.new(0,2,20))
   m:setDefaultCamera(m.camera,initial);m.camera._props.CFrame=initial
   local s=a.init({PredictionX=0,PredictionY=0,WelcomeNotification=false})
   edit(s.ui,"Smoothness",smoothness);s.ui.controls.Enabled.Activated:Fire()
   check(s.config.AngularSafety and s:GetLockedTarget()==target)
   for _=1,15 do
    m:advance(1/60);local d=s.controller:GetDiagnostics()
    check(d.safetyLimited and math.abs(d.pitchRate)<=s.config.PitchMaxSpeed+1e-6)
    -- Ordinary far yaw retains its fast response. The current policy guards
    -- risky near/reversal yaw only and discloses its acceleration separately.
    check(d.yawRate==d.yawRate and math.abs(d.yawRate)<math.huge)
    if d.yawRateGuarded then check(math.abs(d.yawRate)<=s.config.AngularMaxSpeed+1e-6) end
    check(d.yawAccelerationBounded==false)
    check((m.camera.CFrame.Position-initial.Position).Magnitude==0)
   end
   near(s.config.Smoothness,smoothness);near(tonumber(s.ui.controls.Smoothness.Text),smoothness)
   table.insert(errors,s.controller:GetDiagnostics().angularError)
  end
  check(errors[1]>errors[2]+.1,"Smoothness control had no measurable effect after the bounded first frames")
 end)
 test("authorized MISC ESP controls change display finite range and Unlimited",function(m,a)
  m:addPlayer("LoadedRangeTarget",m.env.Vector3.new(0,0,-50))
  local s=a.init({ESP=true,Names=true,ESPAuthorized=true,WelcomeNotification=false});local ui=s.ui
  ui.tabButtons.MISC.Activated:Fire()
  choose(ui,"ESPOcclusionMode","AlwaysOnTop")
  check(s.config.ESPOcclusionMode=="AlwaysOnTop")
  for _,distance in {350,750,1500} do
   edit(ui,"ESPMaxDistance",distance);near(s.config.ESPMaxDistance,distance)
   m:advance(.15);local d=a.GetESPDiagnostics()
   check(d.mode=="AlwaysOnTop" and d.maxDistance==distance and d.loadedDataOnly==true)
   check(d.extendedAuthorized and not d.unlimitedRange)
  end
  ui.controls.ESPUnlimitedRange.Activated:Fire();check(s.config.ESPUnlimitedRange)
  m:advance(.15);local d=a.GetESPDiagnostics()
  check(d.unlimitedRange and d.loadedDataOnly and d.maxDistance==1500)
  ui.controls.ESPUnlimitedRange.Activated:Fire();check(not s.config.ESPUnlimitedRange)
  choose(ui,"ESPOcclusionMode","VisibleOnly");m:advance(.15)
  check(a.GetESPDiagnostics().mode=="VisibleOnly")
 end)
 test("WalkSpeed editable upper bound is 140 and invalid 141 restores last accepted field",function(m,a)
  local s=a.init({MovementMode="Local",LocalMovementAllowed=true,WelcomeNotification=false});local ui=s.ui
  ui:setTab("MISC");ui.controls.Speed.Activated:Fire();check(s.config.Speed)
  local hum=s.registry.entries[s.player].humanoid
  for _,value in {1,140} do edit(ui,"WalkSpeed",value);near(s.config.WalkSpeed,value);near(hum.WalkSpeed,value) end
  local rejected,original={},ui.onNotice
  ui.onNotice=function(reason,field) table.insert(rejected,{reason=reason,field=field});return original(reason,field) end
  edit(ui,"WalkSpeed",141)
  near(s.config.WalkSpeed,140);near(hum.WalkSpeed,140);check(ui.controls.WalkSpeed.Text=="140")
  check(#rejected==1 and rejected[1].field=="WalkSpeed" and rejected[1].reason:find("WalkSpeed",1,true))
  check(not s:configure("WalkSpeed",0) and not s:configure("WalkSpeed",math.huge))
  check(s:GetMovementDiagnostics().Speed.state=="PENDING","property write alone was presented as physical movement")
 end)
 test("unauthorized AlwaysOnTop dropdown rejects without replacing current mode",function(m,a)
  m.services.RunService.IsStudio=function() return false end
  local s=a.init({ESP=true,Names=true,WelcomeNotification=false});local ui=s.ui;ui:setTab("MISC")
  local rejected,original={},ui.onNotice
  ui.onNotice=function(reason,field) table.insert(rejected,{reason=reason,field=field});return original(reason,field) end
  choose(ui,"ESPOcclusionMode","AlwaysOnTop")
  check(s.config.ESPOcclusionMode=="VisibleOnly" and ui.values.ESPOcclusionMode=="VisibleOnly")
  check(ui.controls.ESPOcclusionMode.Text:find("Visible Only",1,true))
  check(#rejected==1 and rejected[1].field=="ESPOcclusionMode" and rejected[1].reason:find("authorized",1,true))
  ui.controls.ESPUnlimitedRange.Activated:Fire()
  check(not s.config.ESPUnlimitedRange and #rejected==2 and rejected[2].field=="ESPUnlimitedRange")
  check(s.config.ESP and not s.destroyed and a.GetESPDiagnostics().loadedDataOnly)
 end)
 test("unavailable movement buttons explain rejected ON and permit OFF after authorization revocation",function(m,a)
  m.services.RunService.IsStudio=function() return false end
  local s=a.init({MovementMode="Local",WelcomeNotification=false});local ui=s.ui;ui:setTab("MISC");m:advance(.6)
  check(ui.controls.Fly.Active and ui.controls.Fly.Text=="OFF" and not s.config.Fly)
  local rejected,original={},ui.onNotice
  ui.onNotice=function(reason,field) table.insert(rejected,{reason=reason,field=field});return original(reason,field) end
  ui.controls.Fly.Activated:Fire()
  check(not s.config.Fly and not s.fly.active and ui.controls.Fly.Text=="OFF")
  check(#rejected==1 and rejected[1].field=="Fly" and type(rejected[1].reason)=="string")
  check(s:configure("LocalMovementAllowed",true));ui.controls.Fly.Activated:Fire()
  check(s.config.Fly and s.fly.active);check(s:configure("LocalMovementAllowed",false));m:advance(.6)
  check(s.config.Fly and not s.fly.active and ui.controls.Fly.Text=="UNAVAILABLE" and ui.controls.Fly.Active)
  ui.controls.Fly.Activated:Fire();check(not s.config.Fly and ui.controls.Fly.Text=="OFF")
  check(s:GetMovementDiagnostics().Fly.state=="OFF" and not s:GetMovementDiagnostics().permitted)
  check(#rejected==1,"permitted OFF unexpectedly reported rejection")
 end)
 test("raw observation errors identify the exact validation phase without changing accepted history",function(m,a)
  local V=m.env.Vector3;local p=engine(a)
  check(p:observe(0,V.new(0,0,-50),"Running"));local prior=p.history:latest()
  for _,row in {
   {math.huge,V.new(0,0,-50),"Running","INVALID_OBSERVATION_TIME"},
   {0,V.new(0,0,-50),"Running","NON_INCREASING_OBSERVATION_TIME"},
   {.1,nil,"Running","INVALID_OBSERVATION_POSITION"},
   {.1,V.new(0/0,0,-50),"Running","INVALID_OBSERVATION_POSITION"},
   {.1,V.new(0,0,-50),{},"INVALID_HUMANOID_STATE"},
   {.1,V.new(13,0,-50),"Running","MOTION_HISTORY_REJECTED"},
  } do
   local accepted,reason=p:observe(row[1],row[2],row[3])
   check(not accepted and reason==row[4],"expected "..row[4]..", got "..tostring(reason))
   check(p.history:latest()==prior,"rejected observation replaced accepted history")
  end
  check(p:observe(.2,V.new(1,0,-50),"Running"));check(p.history:latest()~=prior)
 end)
 test("optional filter speed rejection reports OBSERVED_SPEED_LIMIT before mutating filter",function(m,a)
  local V=m.env.Vector3
  for _,filter in {"OneEuro","AlphaBeta"} do
   local p=engine(a,{MotionFilter=filter});check(p:observe(0,V.new(0,0,-50),"Running"))
   local prior,time,raw=p.history:latest(),p.filter.time,p.filter.raw
   local accepted,reason=p:observe(.1,V.new(13,0,-50),"Running")
   check(not accepted and reason=="OBSERVED_SPEED_LIMIT")
   check(p.history:latest()==prior and p.filter.time==time and p.filter.raw==raw)
   check(p:observe(.2,V.new(1,0,-50),"Running"))
  end
 end)
 test("Session spike rejection remains locked records count throttles logs and resumes accepted observations",function(m,a)
  local V=m.env.Vector3;local target=m:addPlayer("RawSpikeTracking",V.new(0,0,-50))
  local s=a.init({Enabled=true,DebugMode=true,WelcomeNotification=false})
  check(s:GetLockedTarget()==target);local prior;local rejected=0
  for i=1,30 do
   prior=s.prediction.history:latest()
   -- An accepted restore between spikes keeps the valid stream fresh. A
   -- continuous gap exceeding StaleAfter intentionally rebases the history.
   m:move(target,V.new(120*.04+1,0,-50));m:advance(.04)
   local d=a.GetTrackingDiagnostics();rejected+=1
   check(d.locked and d.target==target.Name and d.lastLoss==nil)
   check(d.observation and not d.observation.accepted and d.observation.reason=="MOTION_HISTORY_REJECTED")
   near(d.observation.rejectedCount,rejected);check(s.prediction.history:latest()==prior)
   check(d.observation.lastAcceptedAt==prior.t and d.observation.lastRejectedAt==m:getTime())
   if i<30 then
    m:move(target,V.new(0,0,-50));m:advance(.04)
    check(a.GetTrackingDiagnostics().observation.accepted)
   end
  end
  local notices=0
  for _,entry in m.logs do if entry.text:find("[CamObservation][REJECTED]",1,true) then notices+=1 end end
  check(notices==3,"rejection console diagnostics were silent or exceeded the 1 Hz throttle")
  m:move(target,V.new(0,0,-50));m:advance(.04)
  local d=a.GetTrackingDiagnostics()
  check(d.locked and d.observation.accepted and d.observation.reason==nil)
  near(d.observation.rejectedCount,rejected);near(d.observation.lastAcceptedAt,m:getTime())
  check(d.observation.lastRejectedReason=="MOTION_HISTORY_REJECTED" and s.prediction.history:latest()~=prior)
  check(s:GetPredictedPosition()~=nil and d.trackingState=="TRACKING")
 end)
 test("orientation enum double admits only the two official modes and does not move the character",function(m,a)
  local modes=m.env.Enum.OrientationAlignmentMode
  check(#modes:GetEnumItems()==2 and modes.OneAttachment.EnumType==modes and modes.TwoAttachment.EnumType==modes)
  check(modes.OneAttachment.Value==0 and modes.TwoAttachment.Value==1)
  check(not pcall(function() return modes.InventedMode end),"unknown orientation enum was synthesized")
  local align=m.env.Enum.AlignType
  check(#align:GetEnumItems()==6 and align.AllAxes.Value==5 and align.AllAxes.EnumType==align)
  check(not pcall(function() return align.InventedAlignment end),"unknown alignment enum was synthesized")
  local s=a.init({MovementMode="Local",LocalMovementAllowed=true,WelcomeNotification=false})
  local root=s.registry.entries[s.player].root;local initialPosition=root.Position
  check(s:configure("Fly",true));m:key("W");m:advance(.1)
  check(root.Position==initialPosition and root.AssemblyLinearVelocity==m.env.Vector3.zero,
   "mock invented native movement from a constraint command")
 end)
 print(string.format("SEDWARE V3.2 Session/UI actual-bundle doubles: %d tests, %d assertions, %d failures",tests,checks,failures))
 assert(failures==0,"V3.2 Session/UI regressions failed")
end
