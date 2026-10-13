--!nonstrict
-- V3.1 executes the generated standalone and its embedded modules. All Roblox
-- objects/events/velocities here are explicit doubles: no native physics,
-- third-party integration, real server replication, hit rate or FPS claim.
return function(reloadBundle)
 local Mock=require("./CamV2Mock")
 local tests,checks,failures=0,0,0
 local function check(value,message)
  checks+=1;assert(value,message or ("V3.1 assertion at line "..tostring(debug.info(2,"l"))))
 end
 local function near(actual,expected,tolerance)
  check(type(actual)=="number" and actual==actual and math.abs(actual-expected)<=(tolerance or 1e-8),
   tostring(actual).." ~= "..tostring(expected))
 end
 local function test(name,body)
  tests+=1;local mock=Mock.new();local api=reloadBundle(mock.env)
  local ok,problem=pcall(body,mock,api)
  if not ok then failures+=1;print("FAIL V3.1 "..name..": "..tostring(problem)) end
  api.Unload()
  if mock:countConnections()~=0 or mock:countRenderBindings()~=0 or mock.tweens.active~=0 then
   failures+=1;print("FAIL V3.1 cleanup "..name)
  end
 end
 local function engine(api,overrides)
  local config={Enabled=true,MemoryTracking=false,VelocitySmoothing=.001,WelcomeNotification=false}
  for key,value in overrides or {} do config[key]=value end
  return api.Modules.PredictionEngine.new(assert(api.Modules.Config.new(config)))
 end
 local function phaseSample(prediction,V,t,y,state,expectedPhase)
  check(prediction:observe(t,V.new(t*8,y,-50),state),"phase observation rejected")
  local output=prediction:predict(V.zero,t)
  check(output~=nil,"phase prediction unavailable")
  check(output.movementPhase==expectedPhase,"expected "..expectedPhase..", got "..tostring(output.movementPhase))
  check(math.abs(output.position.Y-output.currentPosition.Y)<=prediction.config.MaxVerticalLead+1e-8,"vertical lead cap exceeded")
  return output
 end
 test("rising apex falling landing and a consecutive jump have separate horizons",function(m,a)
  local V=m.env.Vector3;local p=engine(a)
  phaseSample(p,V,0,0,"Running","Grounded")
  local rising=phaseSample(p,V,.05,2,"Jumping","Rising");near(rising.verticalHorizonUsed,.055)
  phaseSample(p,V,.10,3.5,"Freefall","Rising")
  local apex=phaseSample(p,V,.15,3.55,"Freefall","Apex");near(apex.verticalHorizonUsed,.025)
  check(math.abs(apex.position.Y-apex.currentPosition.Y)<.03,"apex carries rising lead")
  local falling=phaseSample(p,V,.20,3,"Freefall","Falling");near(falling.verticalHorizonUsed,.045)
  check(falling.position.Y<falling.currentPosition.Y)
  local landed=phaseSample(p,V,.25,0,"Landed","Landing")
  near(landed.position.Y,landed.currentPosition.Y);near(landed.verticalVelocityUsed,0)
  phaseSample(p,V,.31,0,"Running","Landing")
  phaseSample(p,V,.40,0,"Running","Grounded")
  local second=phaseSample(p,V,.45,2,"Jumping","Rising")
  check(second.verticalVelocityUsed>0 and second.position.Y>second.currentPosition.Y,"previous landing suppresses consecutive jump")
 end)
 test("vertical lead stays capped when configured horizon and age are large",function(m,a)
  local V=m.env.Vector3;local p=engine(a,{PredictionY=100,RisingHorizon=.35,MaxVerticalLead=2.25})
  p:observe(0,V.new(0,0,-50),"Running");p:observe(.05,V.new(0,4,-50),"Jumping")
  for _,age in {0,.05,.20,.50} do
   local output=p:predict(V.zero,.05+age)
   check(output~=nil and output.verticalLeadLimited)
   near(output.position.Y-output.currentPosition.Y,2.25)
   check(math.abs(output.verticalVelocityUsed)<=85)
  end
 end)
 test("anomalous airborne velocity is bounded and malformed samples do not mutate history",function(m,a)
  local V=m.env.Vector3;local p=engine(a)
  p:observe(0,V.new(0,0,-50),"Running");p:observe(.05,V.new(0,1,-50),"Jumping")
  p:observe(.10,V.new(0,5,-50),"Freefall")
  local output=p:predict(V.zero,.10)
  check(output.verticalAnomaly,"airborne velocity spike was not diagnosed")
  check(output.verticalVelocityUsed<=20+450*.05+1e-8,"spike exceeded acceleration bound")
  local latest=p.history:latest();local phase=p.vertical.phase
  check(not p:observe(.15,V.new(0/0,0,-50),"Freefall"))
  check(not p:observe(math.huge,V.zero,"Freefall"))
  check(not p:observe(.10,V.zero,"Freefall"))
  check(p.history:latest()==latest and p.vertical.phase==phase,"rejected sample mutated tracking state")
  p:observe(.2,V.new(0,0,-50),"Landed")
  output=p:predict(V.zero,.2);near(output.position.Y,0)
 end)
 test("three synthetic jumps preserve all phases at 30 60 120 and 144 Hz",function(m,a)
  local V=m.env.Vector3
  for _,fps in {30,60,120,144} do
   local p=engine(a);local seen={};local jumpCount=0;local previous="Grounded"
   for i=0,math.floor(2.1*fps) do
    local t=i/fps;local cycle=t%.7;local airborne=cycle>0 and cycle<.6
    local y=if airborne then 40*cycle-(40/.6)*cycle*cycle else 0
    local state=if not airborne then "Running" elseif cycle<.3 then "Jumping" else "Freefall"
    check(p:observe(t,V.new(t*12,y,-50),state))
    local output=p:predict(V.zero,t);check(output~=nil)
    seen[output.movementPhase]=true
    if output.movementPhase=="Rising" and previous~="Rising" then jumpCount+=1 end
    previous=output.movementPhase
    check(math.abs(output.position.Y-y)<=2.25+1e-8)
    check(math.abs(output.verticalVelocityUsed)<=85+1e-8)
    check(output.position.Y==output.position.Y and math.abs(output.position.Y)<math.huge)
   end
   check(jumpCount==3,"synthetic jump phase count="..jumpCount.." fps="..fps)
   for _,phase in {"Rising","Apex","Falling","Landing","Grounded"} do check(seen[phase],"missing "..phase.." at "..fps.." Hz") end
  end
 end)
 test("horizontal reversal damps immediately and recovers after its bounded window",function(m,a)
  local V=m.env.Vector3;local p=engine(a)
  p:observe(0,V.new(0,0,-50),"Running");p:observe(.05,V.new(1,0,-50),"Running")
  near(p:predict(V.zero,.05).reversalScale,1)
  p:observe(.10,V.new(0,0,-50),"Running")
  local reversed=p:predict(V.zero,.10)
  near(reversed.reversalScale,.5);near(reversed.horizontalHorizonUsed,.1205*.5)
  check(reversed.position.X<0,"reversal still leads in previous direction")
  local middle=p:predict(V.zero,.14);check(middle.reversalScale>.5 and middle.reversalScale<1)
  local recovered=p:predict(V.zero,.181);near(recovered.reversalScale,1);near(recovered.horizontalHorizonUsed,.1205)
  p:reset();check(p.vertical.reversalAt==nil)
 end)
 test("manual and auto calibrations apply variable RTT exactly once",function(m,a)
  local V=m.env.Vector3
  local curve={{PingMs=60,X=.1,Y=.07},{PingMs=100,X=.13,Y=.09},{PingMs=150,X=.16,Y=.1},{PingMs=300,X=.2,Y=.13}}
  for _,automatic in {false,true} do for i,rtt in {.060,.100,.150,.300} do
   local p=engine(a,{AutoPrediction=automatic,PingReferences=curve,VerticalControl=false})
   p:observe(0,V.new(0,0,-50),"Running");p:observe(.1,V.new(2,0,-50),"Running")
   check(p:samplePing(rtt,.1));local output=p:predict(V.zero,.115)
   local horizon=if automatic then curve[i].X else .1205
   near(output.predictionX,horizon);near(output.ageSeconds,.015);near(output.rawPingMs,rtt*1000)
   near(output.position.X,2+20*(horizon+.015))
   check(math.abs(output.position.X-(2+20*(horizon+.015+rtt)))>.5,"RTT was added twice")
   check(output.observationDelaySeconds==nil and not output.physicsVerified,"unknown capture delay was claimed measured")
  end end
 end)
 test("ping changes preserve bounded automatic slew and unavailable ping falls back",function(m,a)
  local V=m.env.Vector3;local p=engine(a,{AutoPrediction=true,PingSmoothing=.05,PredictionSlew=.06})
  p:observe(0,V.new(0,0,-50),"Running");p:samplePing(.06,0)
  local first=p:predict(V.zero,0);p:samplePing(.3,.1)
  local changed=p:predict(V.zero,.1)
  check(math.abs(changed.predictionX-first.predictionX)<=.006+1e-8,"auto horizon jumped outside slew limit")
  p:samplePing(nil,.11);local fallback=p:predict(V.zero,.11)
  check(fallback.status=="AutoFallback");near(fallback.predictionX,.1205)
  check(fallback.rawPingMs==nil)
 end)
 test("airborne close and polar camera updates remain level and pitch speed is bounded",function(m,a)
  local V,F=m.env.Vector3,m.env.CFrame
  for _,fps in {30,60,120,144} do
   local config=assert(a.Modules.Config.new({Smoothness=0,TrackingMode="Fixed"}))
   local controller=a.Modules.CameraController.new(config);local camera={CFrame=F.new(V.zero)}
   local oldRate=0
   for i=1,fps do
    local target=if i<=fps/2 then V.new(.000001,10,-.000001) else V.new(-.000001,-10,.000001)
    check(controller:update(camera,target,1/fps,{movementPhase="Rising",distanceStuds=2,reversalScale=.5}))
    local d=controller:GetDiagnostics()
    check(math.abs(camera.CFrame.RightVector.Y)<1e-6 and camera.CFrame.UpVector.Y>=0)
    near(d.roll,0,1e-5);check(math.abs(d.pitchRate)<=180+1e-7)
    check(d.safetyLimited and d.angularError==d.angularError)
    if i<fps/2 then check(math.abs(d.pitchRate-oldRate)<=1200/fps+1e-5,"pitch acceleration bound violated") end
    oldRate=d.pitchRate
   end
   controller:reset();check(controller.yaw==nil and controller.pitch==nil)
  end
 end)
 test("ordinary grounded tracking does not receive the vertical safety delay",function(m,a)
  local V,F=m.env.Vector3,m.env.CFrame;local c=a.Modules.CameraController.new(assert(a.Modules.Config.new({Smoothness=0})))
  local camera={CFrame=F.new(V.zero)}
  check(c:update(camera,V.new(30,5,-50),1/60,{movementPhase="Grounded",distanceStuds=50,reversalScale=1}))
  local d=c:GetDiagnostics();check(not d.safetyLimited);check(d.angularError<1e-5)
 end)
 test("temporary missing HitPart pauses without switching players then resumes on replacement",function(m,a)
  local V=m.env.Vector3;local target=m:addPlayer("LockedPlayer",V.new(0,0,-50))
  m:addPlayer("OtherPlayer",V.new(10,0,-50))
  local s=a.init({Enabled=true,SmartSelection=false,WelcomeNotification=false,DebugMode=true})
  check(s:GetLockedTarget()==target)
  local old=s.locked.part;local character=target.Character;old.Parent=nil
  m:advance(.05);local d=a.GetTrackingDiagnostics()
  check(d.target==target.Name and d.locked and d.trackingState=="PAUSED" and d.reason=="HIT_PART_UNAVAILABLE")
  local replacement=m.env.Instance.new("Part");replacement.Name="UpperTorso";replacement.Position=old.Position;replacement.Parent=character
  m:advance(.05);d=s:GetTrackingDiagnostics()
  check(d.target==target.Name and d.trackingState=="TRACKING" and s.locked.part==replacement)
  check(s:GetPredictedPosition()~=nil)
 end)
 test("invalid camera origin and absent local character pause without losing valid target",function(m,a)
  local target=m:addPlayer("CameraOriginTarget",m.env.Vector3.new(0,0,-50))
  local s=a.init({Enabled=true,WelcomeNotification=false})
  check(s:GetLockedTarget()==target)
  local character,frame=s.player.Character,m.camera.CFrame
  -- Explicit exceptional API doubles. This is not ordinary nil-camera
  -- replacement or a claim that a native client produced a NaN CFrame.
  s.player.Character=nil
  m.camera.CFrame=m.env.CFrame.new(m.env.Vector3.new(0/0,2,20))
  check(s.selector:origin()==nil and m.camera.ViewportSize.X>0 and m.camera.ViewportSize.Y>0)
  s:_track(1/60,m:getTime())
  local d=s:GetTrackingDiagnostics()
  check(d.locked and d.target==target.Name and d.trackingState=="PAUSED" and d.reason=="CAMERA_ORIGIN_UNAVAILABLE")
  check(d.lastLoss==nil and not s.manualReleased,"unavailable local origin was reported as a target loss")
  s.player.Character=character;m.camera.CFrame=frame;m:advance(.05)
  d=s:GetTrackingDiagnostics()
  check(s:GetLockedTarget()==target and d.trackingState=="TRACKING" and d.reason==nil and d.pauseReason==nil)
  check(d.lastLoss==nil and s:GetPredictedPosition()~=nil)
 end)
 test("expired HitPart grace records real loss and does not silently reacquire",function(m,a)
  local target=m:addPlayer("LostPart",m.env.Vector3.new(0,0,-50));m:addPlayer("Alternative",m.env.Vector3.new(10,0,-50))
  local s=a.init({Enabled=true,WelcomeNotification=false,DebugMode=true})
  check(s:GetLockedTarget()==target);s.locked.part.Parent=nil
  for _=1,20 do m:advance(.05) end
  local d=s:GetTrackingDiagnostics()
  check(s:GetLockedTarget()==nil and d.trackingState=="LOST" and d.lastLoss.code=="HIT_PART_UNAVAILABLE")
  check(d.lastLoss.target==target.Name and s.manualReleased)
  check(m:hasLog("[CamTarget][HIT_PART_UNAVAILABLE]"))
 end)
 test("target death and range failure carry distinct loss reasons",function(m,a)
  local target=m:addPlayer("RangeLoss",m.env.Vector3.new(0,0,-50))
  local s=a.init({Enabled=true,WelcomeNotification=false});m:move(target,m.env.Vector3.new(0,0,-800));m:advance(.05)
  check(s:GetLockedTarget()==nil and s:GetTrackingDiagnostics().lastLoss.code=="OUT_OF_RANGE")
  m:move(target,m.env.Vector3.new(0,0,-50));check(s:LockTarget(target));m:kill(target)
  check(s:GetLockedTarget()==nil and s:GetTrackingDiagnostics().lastLoss.code=="TARGET_DEAD")
 end)
 test("tracking diagnostics distinguish manual unlock player departure search and disable",function(m,a)
  local target=m:addPlayer("LeavingTarget",m.env.Vector3.new(0,0,-50))
  local s=a.init({Enabled=true,WelcomeNotification=false});local d=a.GetTrackingDiagnostics()
  check(d.locked and d.target==target.Name and d.trackingState=="TRACKING" and d.reason==nil)
  m:key("C");d=s:GetTrackingDiagnostics()
  check(not d.locked and d.target==nil and d.trackingState=="IDLE" and d.lastLoss==nil)
  check(d.reason==nil and d.pauseReason==nil and d.prediction==nil)
  m:advance(.5);check(s:GetTrackingDiagnostics().trackingState=="IDLE" and s:GetLockedTarget()==nil)
  m:key("C",false,true);m:key("C");check(s:GetLockedTarget()==target)
  m:removePlayer(target);d=a.GetTrackingDiagnostics()
  check(not d.locked and d.trackingState=="LOST" and d.reason=="PLAYER_LEFT")
  check(d.lastLoss.code=="PLAYER_LEFT" and d.lastLoss.target==target.Name and d.lastLoss.time==m:getTime())
  m:advance(.5);check(s:GetTrackingDiagnostics().trackingState=="LOST" and s.manualReleased)
  m:key("C",false,true);m:key("C");d=s:GetTrackingDiagnostics()
  check(not d.locked and d.trackingState=="SEARCHING" and type(d.reason)=="string" and #d.reason>0)
  check(s:SetEnabled(false));d=s:GetTrackingDiagnostics();check(not d.locked and d.trackingState=="DISABLED" and d.reason==nil)
  m:key("C",false,true);m:key("C");check(s:GetTrackingDiagnostics().trackingState=="DISABLED")
  local second=m:addPlayer("ManualPausedTarget",m.env.Vector3.new(0,0,-50));check(s:SetEnabled(true))
  check(s:GetLockedTarget()==second);s.locked.part.Parent=nil;m:advance(.05)
  check(s:GetTrackingDiagnostics().trackingState=="PAUSED")
  m:key("C",false,true);m:key("C");d=s:GetTrackingDiagnostics()
  check(not d.locked and d.trackingState=="IDLE" and d.reason==nil and d.pauseReason==nil)
  check(d.lastLoss.code=="PLAYER_LEFT","manual unlock was misreported as a new actual loss")
 end)
 test("C unlocks and relocks a player while movement edits preserve selection",function(m,a)
  local target=m:addPlayer("CPlayer",m.env.Vector3.new(0,0,-50))
  local s=a.init({Enabled=true,MovementMode="Local",LocalMovementAllowed=true,WelcomeNotification=false})
  check(s:GetLockedTarget()==target);m:key("C");check(s:GetLockedTarget()==nil)
  m:key("C",false,true);m:key("C");check(s:GetLockedTarget()==target)
  check(s:configure("Speed",true));check(s:configure("FlySpeed",80));check(s:configure("ESP",true))
  check(s:GetLockedTarget()==target and s:GetPredictedPosition()~=nil)
 end)
 test("explicit permitted Local route works without installed server bridge",function(m,a)
  local s=a.init({MovementMode="Local",LocalMovementAllowed=true,WelcomeNotification=false})
  check(not s.movementBridge.available);local hum=s.registry.entries[s.player].humanoid
  check(s:configure("Speed",true));near(hum.WalkSpeed,24)
  local d=a.GetMovementDiagnostics();check(d.mode=="Local" and d.permitted and d.Speed.state=="LOCAL ONLY" and not d.Speed.effective)
  check(s:configure("Speed",false));near(hum.WalkSpeed,16)
  check(s:configure("Fly",true));check(s.fly.constraint and s.fly.constraint:IsA("LinearVelocity"))
  d=s:GetMovementDiagnostics();check(d.Fly.state=="LOCAL ONLY" and not d.Fly.effective)
  check(not s:configure("MovementMode","Server"),"active local route changed without releasing controls")
 end)
 test("Server route rejects missing own component despite local permission",function(m,a)
  local s=a.init({MovementMode="Server",LocalMovementAllowed=true,MovementAuthorized=true,WelcomeNotification=false})
  local ok,reason=s:configure("Fly",true)
  check(not ok and reason:find("Server",1,true)~=nil and not s.config.Fly)
  check(not s:configure("Speed",true));check(s:GetMovementDiagnostics().Fly.state=="UNAVAILABLE")
  near(m:liveInstances("LinearVelocity"),0)
 end)
 test("local velocity observation distinguishes installed fly from effective movement",function(m,a)
  local s=a.init({MovementMode="Local",LocalMovementAllowed=true,WelcomeNotification=false,FlySmoothing=0})
  check(s:configure("Fly",true));m:key("Space");m:advance(.05)
  local root=s.registry.entries[s.player].root;local requested=s.fly.constraint.VectorVelocity
  check(requested.Y>1);local d=s:GetMovementDiagnostics()
  check(d.Fly.state=="LOCAL ONLY" and not d.Fly.effective,"constraint installation was presented as physical movement")
  -- Explicit velocity fixture; Roblox physics did not generate this value.
  root.AssemblyLinearVelocity=requested;d=s:GetMovementDiagnostics()
  check(d.Fly.state=="LOCAL ACTIVE" and d.Fly.effective)
  check(d.Fly.reason:find("replication unverified",1,true)~=nil)
  root.AssemblyLinearVelocity=-requested;d=s:GetMovementDiagnostics();check(not d.Fly.effective,"opposite velocity accepted as successful fly")
  root.AssemblyLinearVelocity=m.env.Vector3.zero
  for _=1,30 do m:advance(.05) end
  d=s:GetMovementDiagnostics();check(d.Fly.state=="SERVER LIMITED" and not d.Fly.effective)
  check(d.Fly.reason:find("unconfirmed",1,true)~=nil,"inferred restriction was claimed confirmed")
  check(s:configure("Fly",false));near(m:liveInstances("LinearVelocity"),0)
 end)
 test("WalkSpeed override reports SERVER LIMITED and never fights the override",function(m,a)
  local s=a.init({MovementMode="Local",LocalMovementAllowed=true,WelcomeNotification=false})
  local hum=s.registry.entries[s.player].humanoid;check(s:configure("Speed",true))
  local writes=s.speed.writes;hum.WalkSpeed=12
  for _=1,120 do m:advance(1/60) end
  local d=s:GetMovementDiagnostics();near(hum.WalkSpeed,12);near(s.speed.writes,writes)
  check(d.Speed.state=="SERVER LIMITED" and not d.Speed.controllerActive and not d.Speed.effective)
  check(s:configure("Speed",false));near(hum.WalkSpeed,12)
 end)
 test("anchoring a local character suspends constraints and resumes after unanchoring",function(m,a)
  local s=a.init({MovementMode="Local",LocalMovementAllowed=true,WelcomeNotification=false})
  local entry=s.registry.entries[s.player];check(s:configure("Fly",true))
  entry.root.Anchored=true;m:advance(.05)
  check(not s.fly.active and s.config.Fly and entry.root:FindFirstChild("SEDWAREFlyVelocity")==nil)
  check(s:GetMovementDiagnostics().Fly.state=="UNAVAILABLE")
  check(entry.humanoid.AutoRotate and not entry.humanoid.PlatformStand)
  entry.root.Anchored=false;m:advance(.05)
  check(s.fly.active and entry.root:FindFirstChild("SEDWAREFlyVelocity")~=nil)
  check(s:GetMovementDiagnostics().Fly.state=="LOCAL ONLY","resuming constraints falsely confirmed physics")
 end)
 test("local permission revocation stops movement without modifying another controller",function(m,a)
  m.services.RunService.IsStudio=function() return false end
  local s=a.init({MovementMode="Local",LocalMovementAllowed=true,WelcomeNotification=false})
  local entry=s.registry.entries[s.player];check(s:configure("Speed",true));near(entry.humanoid.WalkSpeed,24)
  check(s:configure("LocalMovementAllowed",false));m:advance(.05)
  near(entry.humanoid.WalkSpeed,16);check(not s.speed.active)
  local d=s:GetMovementDiagnostics();check(not d.permitted and d.Speed.state=="UNAVAILABLE")
  check(not s:configure("Fly",true));near(m:liveInstances("LinearVelocity"),0)
 end)
 test("late own bridge releases local controllers before capturing server baselines",function(m,a)
  local storage=m.env.Instance.new("Folder");storage.Name="ReplicatedStorage"
  local control=m.env.Instance.new("RemoteFunction");control.Name="SEDWAREMovementControl";control.Parent=storage
  local input=m.env.Instance.new("RemoteEvent");input.Name="SEDWAREMovementInput";input.Parent=storage
  local oldService=m.env.game.GetService
  m.env.game.GetService=function(self,name) if name=="ReplicatedStorage" then return storage end;return oldService(self,name) end
  local entry,requestSeen,requestToken
  control.InvokeServer=function(_,request)
   requestSeen=true;requestToken=request.token
   near(entry.humanoid.WalkSpeed,16)
   check(entry.humanoid.AutoRotate and not entry.humanoid.PlatformStand,"local Fly flags reached own server baseline")
   check(entry.root:FindFirstChild("SEDWAREFlyVelocity")==nil and entry.root:FindFirstChild("SEDWAREFlyAttachment")==nil,"local constraint survived Auto route transition")
   if request.speed and not request.fly then entry.humanoid.WalkSpeed=request.walkSpeed end
   local p=m.services.Players.LocalPlayer;p:SetAttribute("SEDWAREMovementToken",request.token)
   p:SetAttribute("SEDWAREServerFlyActive",request.fly);p:SetAttribute("SEDWAREServerSpeedActive",request.speed and not request.fly)
   return {ok=true,reason="Explicit own-protocol stub; physical execution unverified"}
  end
  input.FireServer=function(_,token,value)
   if token==requestToken and value=="Stop" then
    entry.humanoid.WalkSpeed=16
    local p=m.services.Players.LocalPlayer;p:SetAttribute("SEDWAREServerFlyActive",false);p:SetAttribute("SEDWAREServerSpeedActive",false)
   end
  end
  for _,field in {"Speed","Fly"} do for _,beforeFirstFrame in {false,true} do
   a.Unload();m.world:SetAttribute("SEDWAREMovementProtocolVersion",nil)
   local s=a.init({MovementMode="Auto",LocalMovementAllowed=true,WelcomeNotification=false})
   entry=s.registry.entries[s.player];requestSeen=false;requestToken=nil
   check(not s.movementBridge.available);check(s:configure(field,true))
   if field=="Fly" then check(s.fly.active and s.fly.constraint~=nil) else near(entry.humanoid.WalkSpeed,24) end
   if not beforeFirstFrame then m:advance(.05) end
   s.player:SetAttribute("SEDWAREMovementAuthorized",true);m.world:SetAttribute("SEDWAREMovementProtocolVersion",1)
   for _=1,14 do m:advance(.05) end
   check(requestSeen and s.movementBridge.available and s.movementBridge.active,"own bridge baseline request was rejected: "..tostring(s.movementBridge.reason))
   check(s:GetMovementDiagnostics().mode=="Server" and s.config[field])
   check(s.fly.constraint==nil and s.speed.humanoid==nil,"local controller retained ownership after server confirmation")
   a.Unload();near(entry.humanoid.WalkSpeed,16)
  end end
 end)
 test("V3.1 GUI dimensions title and minimize restore retain configuration",function(m,a)
  local s=a.init({WelcomeNotification=false});local ui=s.ui
  check(ui.title.Text=="SEDWARE V3.1");near(ui.panel.Size.X.Offset,420);near(ui.panel.Size.Y.Offset,520)
  near(s.config.PredictionX,13.15);near(s.config.PredictionY,13.15)
  ui:setTab("MISC");ui:setMinimized(true);m:advance(.23);near(ui.panel.Size.Y.Offset,56)
  ui:setMinimized(false);m:advance(.23)
  check(ui.tab=="MISC" and not ui.minimized);near(ui.panel.Size.X.Offset,420);near(ui.panel.Size.Y.Offset,520)
  check(ui.logo:FindFirstChild("TemporaryFallback").Visible,"missing original asset fallback disappeared")
 end)
 test("baseline ESP rejects 750 and 1500 studs and extended configured range admits loaded players",function(m,a)
  local V=m.env.Vector3;local nearPlayer=m:addPlayer("NearLoaded",V.new(0,0,-100))
  local medium=m:addPlayer("MediumLoaded",V.new(0,0,-730));local far=m:addPlayer("FarLoaded",V.new(0,0,-1480))
  local s=a.init({ESP=true,Hitboxes=true,Names=true,WelcomeNotification=false})
  m:advance(.11);check(s.esp.stats.visible==1 and s.esp.stats.outOfRange==2 and s.esp.renderers[nearPlayer]~=nil)
  check(s:configure("ESPMaxDistance",750));m:advance(.4)
  check(s.esp.renderers[medium]~=nil and s.esp.stats.visible==2)
  check(s:configure("ESPMaxDistance",1500));m:advance(.4)
  check(s.esp.renderers[far]~=nil and s.esp.stats.visible==3)
  local before=s.esp.stats.created
  for _=1,100 do m:advance(.05) end
  near(s.esp.stats.created,before)
  check(s:configure("ESP",false));near(m:liveInstances("SelectionBox"),0);near(m:liveInstances("BillboardGui"),0)
 end)
 test("extended ESP options require authorization and preserve finite config bounds",function(m,a)
  -- Base double is Studio. Explicitly model a published, unauthorized client.
  m.services.RunService.IsStudio=function() return false end
  local s=a.init({WelcomeNotification=false})
  check(not s:configure("ESPOcclusionMode","AlwaysOnTop"),"wall visibility accepted without owned debug authorization")
  check(not s:configure("ESPUnlimitedRange",true),"unlimited loaded-player range accepted without owned debug authorization")
  check(s:configure("ESPAuthorized",true))
  check(s:configure("ESPOcclusionMode","AlwaysOnTop"));check(s:configure("ESPUnlimitedRange",true))
  check(not s:configure("ESPMaxDistance",math.huge));check(not s:configure("ESPFarUpdateHz",0))
  check(not s:configure("MovementMode","External"));check(not s:configure("RisingHorizon",-.1))
 end)
 test("revoking an ESP grant permits ordinary edits safe reset and VisibleOnly restart",function(m,a)
  m.services.RunService.IsStudio=function() return false end
  m.world:SetAttribute("SEDWAREESPAuthorized",true)
  local target=m:addPlayer("RevokedGrantPlayer",m.env.Vector3.new(0,0,-50))
  local s=a.init({ESP=true,Names=true,Hitboxes=true,ESPUnlimitedRange=true,ESPOcclusionMode="AlwaysOnTop",WelcomeNotification=false})
  m:advance(.1);check(s.esp.renderers[target]~=nil)
  m.world:SetAttribute("SEDWAREESPAuthorized",false);m:advance(.1)
  check(not s.config.ESP and not s.destroyed and s.esp.destroyed)
  check(s:configure("Enabled",true));check(s:configure("PredictionX",14.20));check(s:configure("ESP",false))
  check(s:configure("ESPOcclusionMode","VisibleOnly"));check(s:configure("ESPUnlimitedRange",false))
  check(s:configure("ESP",true));m:advance(.15)
  check(s.esp.renderers[target]~=nil and s.esp.renderers[target].billboard.Enabled)
  check(not s:configure("ESPOcclusionMode","AlwaysOnTop"));check(not s:configure("ESPUnlimitedRange",true))
  check(s:GetLockedTarget()==target and s:GetPredictedPosition()~=nil)
 end)
 test("ESP mode rebuild retains applied Specific Player selection rather than username draft",function(m,a)
  local first=m:addPlayer("AppliedPlayer",m.env.Vector3.new(0,0,-50))
  local draft=m:addPlayer("DraftPlayer",m.env.Vector3.new(10,0,-50))
  local s=a.init({ESP=true,Names=true,ESPAuthorized=true,WelcomeNotification=false})
  check(s:configure("ESPUsername","AppliedPlayer"));check(s:ApplyESPTarget());m:advance(.15)
  check(s.esp.renderers[first]~=nil and s.esp.renderers[draft]==nil)
  check(s:configure("ESPUsername","DraftPlayer"));check(s:configure("ESPOcclusionMode","AlwaysOnTop"));m:advance(.15)
  check(s.esp.renderers[first]~=nil and s.esp.renderers[draft]==nil,"mode switch silently applied username draft")
  check(s.config.ESPUsername=="DraftPlayer" and s.esp.selectedUsername=="appliedplayer")
  check(s:ClearESPTarget());check(s.esp.renderers[first]==nil and s.esp.selectedUsername==nil)
  check(s:configure("ESPOcclusionMode","VisibleOnly"));m:advance(.15)
  check(next(s.esp.renderers)==nil and s.esp.selectedUsername==nil,"cleared Specific selection reappeared on mode rebuild")
 end)
 test("authorized AlwaysOnTop can show a loaded occluded player without resizing physics",function(m,a)
  local target=m:addPlayer("DebugOccluded",m.env.Vector3.new(0,0,-50));m:setOccluded(target,true)
  local root=target.Character:FindFirstChild("HumanoidRootPart");local size=root.Size
  local s=a.init({ESP=true,Names=true,Hitboxes=true,ESPAuthorized=true,ESPOcclusionMode="AlwaysOnTop",WelcomeNotification=false})
  m:advance(.11);local r=s.esp.renderers[target]
  check(r~=nil and r.billboard.Enabled and r.billboard.AlwaysOnTop)
  near(s.esp.stats.raycasts,0)
  check(root.Size==size and root.Anchored==false,"ESP changed physical character")
  check(s:configure("ESPOcclusionMode","VisibleOnly"));m:advance(.4)
  check(r.destroyed and r.billboard==nil and r.screenBox==nil and r.highlight==nil,"previous through-wall indicators survived mode switch")
  check(s.esp.renderers[target]==nil and s.esp.stats.visible==0)
  m:setOccluded(target,false);m:advance(.4)
  r=s.esp.renderers[target];check(r~=nil)
  check(r.box~=nil and r.box.Visible and r.billboard.Enabled and not r.billboard.AlwaysOnTop)
  check(r.box.Adornee==root and r.screenBox==nil and r.highlight==nil)
 end)
 test("unlimited authorized range includes only registered loaded characters",function(m,a)
  local target=m:addPlayer("VeryFarLoaded",m.env.Vector3.new(0,0,-3000))
  local s=a.init({ESP=true,Names=true,ESPAuthorized=true,ESPUnlimitedRange=true,WelcomeNotification=false})
  m:advance(.4);check(s.esp.renderers[target]~=nil and s.esp.stats.visible==1)
  local r=s.esp.renderers[target];check(r.billboard.MaxDistance==0,"unlimited range still capped native name rendering")
  local character=target.Character;character.Parent=nil;m:advance(.4)
  check(not r.billboard.Enabled and s.esp.stats.visible==0,"unloaded character was reconstructed")
  character.Parent=m.world;m:advance(.4);check(r.billboard.Enabled)
  m:removePlayer(target);check(s.esp.renderers[target]==nil)
 end)
 test("far indicators use lower bounded cadence and cache players without per-frame allocation",function(m,a)
  local nearPlayer=m:addPlayer("CadenceNear",m.env.Vector3.new(0,0,-100))
  local farPlayer=m:addPlayer("CadenceFar",m.env.Vector3.new(0,0,-1000))
  local s=a.init({ESP=true,Hitboxes=true,Names=true,ESPMaxDistance=1500,ESPFarDistance=350,ESPFarUpdateHz=3,WelcomeNotification=false})
  m:advance(.30);local nearRenderer,farRenderer=s.esp.renderers[nearPlayer],s.esp.renderers[farPlayer]
  check(nearRenderer~=nil and farRenderer~=nil)
  local nearCalls,farCalls=0,0;local nearSync,farSync=nearRenderer.sync,farRenderer.sync
  nearRenderer.sync=function(self,...) nearCalls+=1;return nearSync(self,...) end
  farRenderer.sync=function(self,...) farCalls+=1;return farSync(self,...) end
  local created=s.esp.stats.created;local connections=m:countConnections();m:resetCounters()
  for _=1,144 do m:advance(1/144) end
  check(nearCalls>=8 and nearCalls<=11,"near indicator cadence="..nearCalls)
  check(farCalls>=2 and farCalls<=4 and farCalls<nearCalls,"far indicator cadence="..farCalls)
  near(s.esp.stats.created,created);near(m:countConnections(),connections);near(m.counters.candidateScans,0)
 end)
 print(string.format("SEDWARE V3.1 actual-bundle doubles: %d tests, %d assertions, %d failures",tests,checks,failures))
 assert(failures==0,"V3.1 bundle regressions failed")
end
