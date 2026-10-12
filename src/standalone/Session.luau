--!nonstrict
-- Single-client laboratory. All test shots are local measurements, never weapon
-- commands, damage, or protected communications in another experience.
local Configuration = if script then require(script.Parent.Configuration) else require("./Configuration")
local Calibration = if script then require(script.Parent.Calibration) else require("./Calibration")
local Interface = if script then require(script.Parent.Interface) else require("./Interface")
local Predictor = if script then require(script.Parent.Parent.shared.Predictor) else require("../shared/Predictor")
local Settings = if script then require(script.Parent.Parent.shared.Settings) else require("../shared/Settings")
local Diagnostics = if script then require(script.Parent.Parent.shared.Diagnostics) else require("../shared/Diagnostics")
local Geometry = if script then require(script.Parent.Parent.shared.Geometry) else require("../shared/Geometry")
local Runtime = if script then require(script.Parent.Runtime) else require("./Runtime")
local Session = {}
Session.__index = Session
local MAX_RANGE = 400
local MAX_PENDING = 96
local MAX_PROJECTILES = 24
local MEASUREMENT_INTERVAL = 0.2

local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function vecOK(v) return typeof(v)=="Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z) end
local function copyCore(from, into)
 for k,v in from do into[k]=v end
end
local function connection(self, signal, callback)
 local c=signal:Connect(callback);table.insert(self.connections,c);return c
end
local function now() return workspace:GetServerTimeNow() end
local function positionAt(spec, t)
 local elapsed=t-spec.epoch+spec.phase
 local phase=(elapsed/spec.period)%1
 local x=spec.width*(1-4*math.abs(phase-0.5))
 local vx=(if phase<0.5 then 1 else -1)*4*spec.width/spec.period
 local jump=(elapsed%3.4)-1.8
 local y,vy,state=0,0,"running"
 if jump>=0 and jump<1.2 then
  y=24*jump-20*jump*jump;vy=24-40*jump;state=if vy>0 then "jumping" else "falling"
 end
 return spec.base+Vector3.new(x,y,4*math.sin(elapsed*0.9)),
  Vector3.new(vx,vy,3.6*math.cos(elapsed*0.9)),state
end

function Session:_origin()
 local character=self.player.Character
 local head=character and character:FindFirstChild("Head")
 if head and head:IsA("BasePart") then return head.Position end
 local root=character and character:FindFirstChild("HumanoidRootPart")
 return if root and root:IsA("BasePart") then root.Position+Vector3.new(0,1.5,0) else nil
end
function Session:_part(name, size, color)
 local p=Instance.new("Part")
 p.Parent=self.world
 p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
 p.Size=size;p.Color=color;p.Material=Enum.Material.Neon;p.CastShadow=false
 return p
end
function Session:_createTargets()
 if #self.specs>0 then return end
 local origin=self:_origin()
 if not origin then return end
 local camera=workspace.CurrentCamera
 local forward=if camera then camera.CFrame.LookVector else Vector3.new(0,0,-1)
 forward=Vector3.new(forward.X,0,forward.Z)
 if forward.Magnitude<0.1 then forward=Vector3.new(0,0,-1) else forward=forward.Unit end
 for i, distance in {28,80,150} do
  local id=({"near","mid","far"})[i]
  local p=self:_part(id,Vector3.new(4,4,4),({Color3.fromRGB(74,177,255),Color3.fromRGB(100,214,235),Color3.fromRGB(165,146,255)})[i])
  p.Shape=Enum.PartType.Ball
  local spec={id=id,part=p,radius=2,base=origin+forward*distance,
   width=10+i*3,period=4+i*0.5,phase=(i-1)*1.1,epoch=now()}
  table.insert(self.specs,spec)
 end
end
function Session:_newPredictors()
 self.predictor=Predictor.new(self.config.core)
 self.autoCore=Settings.new();self.manualCore=Settings.new()
 self.autoPredictor=Predictor.new(self.autoCore);self.manualPredictor=Predictor.new(self.manualCore)
 -- Both alternatives reuse the very same bounded Memory history; only latency
 -- filters differ. No future truth is supplied to any of these predictors.
 self.autoPredictor.tracks=self.predictor.tracks;self.manualPredictor.tracks=self.predictor.tracks
 self.targets={};self.selected=nil;self.solution=nil;self.drawPoint=nil
 self.lastPingSample=nil
end
function Session:_resetTracking()
 self:_newPredictors();table.clear(self.pending);table.clear(self.shots)
 for _, projectile in self.projectiles do projectile.part:Destroy() end
 table.clear(self.projectiles)
end
function Session:_clearMeasurements()
 table.clear(self.pending);self.calibration:clear();self.diagnostics:clear();self.lastError=nil
end
function Session:_replaceConfig(config)
 self.config=config;self:_resetTracking();self.calibration:clear();self.diagnostics:clear()
 self.lastError=nil;self.ui:setConfig(config)
end
function Session:_change(path,value)
 local candidate=Configuration.createSnapshot(self.config)
 local object=candidate
 local keys=string.split(path,".")
 if keys[1]=="profile" then object=candidate.profiles[candidate.activeProfile];table.remove(keys,1) end
 for i=1,#keys-1 do
  if type(object[keys[i]])~="table" then return false,"Campo desconocido" end
  object=object[keys[i]]
 end
 local key=keys[#keys]
 if object[key]==nil then return false,"Campo desconocido" end
 object[key]=value
 local ok,message=Configuration.validate(candidate)
 if not ok then return false,message end
 local reset=path=="targetMode" or path=="core.memoryTracking" or path=="activeProfile"
 if reset then
  self.config=candidate;self:_resetTracking();self.ui:setConfig(candidate)
 else
  -- Mutate the existing root settings object, preserving predictor references.
  local originalCore=self.config.core
  copyCore(candidate.core,originalCore);candidate.core=originalCore;self.config=candidate
  self.ui:setConfig(candidate)
 end
 -- Do not mix training from different latency/physics assumptions. Display and
 -- selection-only controls can retain the same measurement window.
 local retain=path=="core.enabled" or path=="core.debugVisualization" or path=="core.fovPixels"
  or path=="core.maxTargetDistanceStuds" or path=="predictionSmoothingSeconds" or path=="adaptiveCalibration"
 if not retain then self:_clearMeasurements() end
 return true
end
function Session:_ping(t)
 if self.lastPingSample and t-self.lastPingSample<0.2 then return end
 self.lastPingSample=t
 if self.config.useSimulatedPing then self.rtt=self.config.simulatedRTTMilliseconds/1000
 else
  local ok,value=pcall(function() return self.player:GetNetworkPing() end)
  if ok and finite(value) and value>=0 and value<=2 then self.rtt=value
  else self.rtt=nil end
 end
 self.actualOneWay=(self.rtt or 0)/2
 local input=if self.config.pingCompensation then self.actualOneWay else 0
 self.predictor:setPing(input,t);self.autoPredictor:setPing(input,t);self.manualPredictor:setPing(input,t)
end
function Session:_observe(t)
 local present={}
 if self.config.targetMode=="Simulated" then
  self:_createTargets()
  local stamp=t-self.actualOneWay-self.config.simulatedObservationDelaySeconds
  for _, spec in self.specs do
   spec.part.Transparency=0
   local current=positionAt(spec,t);spec.part.Position=current
   local p,v,state=positionAt(spec,stamp)
   local sample={t=stamp,position=p,velocity=v,state=state}
   self.targets[spec.id]={sample=sample,current=current,spec=spec,radius=spec.radius}
   self.predictor:observe(spec.id,sample);present[spec.id]=true
  end
 else
  for _,spec in self.specs do spec.part.Transparency=1 end
  for _,player in self.services.Players:GetPlayers() do
   if player~=self.player then
    local character=player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    if root and root:IsA("BasePart") and humanoid and humanoid.Health>0 and root:IsDescendantOf(workspace) then
     local id="player:"..player.UserId
     -- Timestamp is local capture time, NOT authoritative replication time.
     -- Derive velocity from positions; AssemblyLinearVelocity is NotReplicated.
     local sample={t=t,position=root.Position,state=humanoid:GetState().Name}
     if vecOK(sample.position) then
      self.targets[id]={sample=sample,current=root.Position,model=character,radius=2}
      self.predictor:observe(id,sample);present[id]=true
     end
    end
   end
  end
 end
 for id in self.targets do
  if not present[id] then self.targets[id]=nil;self.predictor:forget(id) end
 end
end
function Session:_params(excludeCharacters)
 local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude
 local exclusions={self.world}
 if self.player.Character then table.insert(exclusions,self.player.Character) end
 if excludeCharacters then
  for _,target in self.targets do if target.model then table.insert(exclusions,target.model) end end
 end
 p.FilterDescendantsInstances=exclusions;p.IgnoreWater=true
 return p
end
function Session:_select(t)
 local origin=self:_origin();local camera=workspace.CurrentCamera
 if not self.config.core.enabled or not camera or not origin then self.selected=nil;self.solution=nil;return end
 if not self.ui:isPointerOver() and not self.services.UserInputService:GetFocusedTextBox() then
  self.selectionMouse=self.services.UserInputService:GetMouseLocation()
 end
 local viewportMouse=self.selectionMouse-self.services.GuiService:GetGuiInset()
 local params=self:_params(true)
 local function valid(id)
  local target=self.targets[id]
  if not target or t-target.sample.t>self.config.core.staleAfterSeconds then return nil end
  local distance=(target.sample.position-origin).Magnitude
  if distance>math.min(MAX_RANGE,self.config.core.maxTargetDistanceStuds) then return nil end
  local point,onScreen=camera:WorldToViewportPoint(target.current)
  if not onScreen or point.Z<=0 then return nil end
  local pixels=(Vector2.new(point.X,point.Y)-viewportMouse).Magnitude
  if pixels>self.config.core.fovPixels then return nil end
  local delta=target.current-camera.CFrame.Position
  local obstacle=workspace:Raycast(camera.CFrame.Position,delta,params)
  if obstacle and obstacle.Distance<delta.Magnitude-0.25 then return nil end
  return pixels
 end
 if not self.selected or not valid(self.selected) then
  self.selected=nil;self.drawPoint=nil
  local best=math.huge
  for id in self.targets do
   local pixels=valid(id)
   if pixels and pixels<best then best=pixels;self.selected=id end
  end
 end
 if self.selected then
  local target=self.targets[self.selected]
  local distance=(target.sample.position-origin).Magnitude
  Configuration.prepareCore(self.config,distance)
  self.profile=Configuration.getProfile(self.config,distance)
  copyCore(self.config.core,self.autoCore);self.autoCore.autoPrediction=true
  copyCore(self.config.core,self.manualCore);self.manualCore.autoPrediction=false
  self.solution=self.predictor:predict(self.selected,origin,t,self.profile)
 else self.solution=nil end
end
function Session:_queueMeasurements(t)
 if not self.selected or not self.solution or self.config.targetMode~="Simulated" or #self.pending>MAX_PENDING-3 then return end
 local target=self.targets[self.selected]
 local origin=self:_origin()
 if not target or not target.spec or not origin then return end
 local mode=if self.config.core.autoPrediction then "auto" else "manual"
 for _,pair in {{self.predictor,mode,true},{self.autoPredictor,"auto",false},{self.manualPredictor,"manual",false}} do
  local result=pair[1]:predict(self.selected,origin,t,self.profile)
  if result then
   -- The reference time comes from the MODEL'S actual transport delay, not
   -- the configured prediction delay; incorrect offsets therefore cause error.
   local due=t+self.actualOneWay+result.flightSeconds
   table.insert(self.pending,{due=due,created=t,spec=target.spec,result=result,
    weapon=self.config.activeProfile,range=result.range,mode=pair[2],primary=pair[3]})
  end
 end
end
function Session:_measure(t)
 for i=#self.pending,1,-1 do
  local m=self.pending[i]
  if m.due<=t then
   local truth,velocity,state=positionAt(m.spec,m.due)
   local residual=truth-m.result.targetPosition
   local record={type="prediction",weapon=m.weapon,range=m.range,mode=m.mode,
    errorStuds=residual.Magnitude,sampleTime=m.result.sampleTime,impactTime=m.due,now=t}
   if m.primary then self.lastError=record.errorStuds;self.diagnostics:recordPrediction(record)
   else
    local v=m.result.velocity
    -- Exclude state transitions/turns from latency training, while retaining
    -- their errors in the RMSE comparison. Otherwise motion error becomes bias.
    local stable=state==m.result.state and v.Magnitude>2 and velocity.Magnitude>2
      and v:Dot(velocity)/(v.Magnitude*velocity.Magnitude)>0.85
    record.residual=residual;record.velocity=if stable then v else v*0
    self.calibration:record(record)
   end
   table.remove(self.pending,i)
  end
 end
end
function Session:_applyCalibration(automatic,t)
 if not self.solution or self.config.targetMode~="Simulated" then return false,"Calibración requiere verdad del blanco simulado" end
 if automatic and not self.config.core.autoPrediction then return false,"Modo manual activo" end
 local range=self.solution.range
 local correction,count=self.calibration:suggest(self.config.activeProfile,range,t)
 if count<20 then return false,"Se requieren 20 mediciones automáticas de movimiento estable" end
 local profile=self.config.profiles[self.config.activeProfile]
 local step=math.clamp(correction,-0.002,0.002) -- at most 2 ms per application
 local previous=profile.rangeOffsets[range]
 profile.rangeOffsets[range]=math.clamp(previous+step,-0.15,0.15)
 self.ui:setConfig(self.config)
 local message=string.format("Corrección gradual: %+.1f ms (%s)",step*1000,range)
 if not automatic then self.ui:setStatus(message) end
 self.lastCalibration=t
 return true,message
end
function Session:_trace(origin,to,t)
 if (to-origin).Magnitude<0.01 then return end
 local p=self:_part("LocalShotTrace",Vector3.new(0.05,0.05,(to-origin).Magnitude),Color3.fromRGB(81,159,255))
 p.CFrame=CFrame.lookAt((origin+to)/2,to)
 table.insert(self.effects,{part=p,due=t+0.12})
end
function Session:fire()
 if self.destroyed or self.paused or not self.config.core.enabled then return end
 local t=now();self:_select(t)
 local origin=self:_origin();local target=self.selected and self.targets[self.selected]
 if not origin or not target or not self.solution then self.ui:setStatus("Selecciona un blanco visible dentro del FOV",true);return end
 local profile=Configuration.getProfile(self.config,self.solution.distanceStuds)
 if profile.kind=="projectile" and profile.radius>0 and not self.compatibility.capabilities.spherecast then
  self.ui:setStatus("Spherecast no disponible: el tiro con radio no puede comprobarse. Usa radio 0 para raycast.",true);return
 end
 if t<self.nextFire then return end
 local prediction=self.predictor:predict(self.selected,origin,t,profile)
 if not prediction or (prediction.position-origin).Magnitude<0.001 then return end
 if #self.shots>=16 or #self.projectiles+#self.shots>=MAX_PROJECTILES then self.ui:setStatus("Límite de tiros locales en vuelo",true);return end
 self.nextFire=t+profile.cooldown
 local direction=(prediction.position-origin).Unit
 if profile.spreadRadians>0 then
  local axis=if math.abs(direction.Y)>0.95 then Vector3.xAxis else Vector3.yAxis
  local right=direction:Cross(axis).Unit;local up=right:Cross(direction).Unit
  local cosine=1-self.random:NextNumber()*(1-math.cos(profile.spreadRadians))
  local sine=math.sqrt(math.max(0,1-cosine*cosine));local angle=self.random:NextNumber(0,2*math.pi)
  direction=(direction*cosine+(right*math.cos(angle)+up*math.sin(angle))*sine).Unit
 end
 table.insert(self.shots,{due=t+self.actualOneWay,origin=origin,direction=direction,
  profile=profile,weapon=self.config.activeProfile,id=self.selected,target=target,mode=self.config.targetMode})
 self.ui:setStatus("Disparo local de laboratorio; sin daño ni evento de arma")
end
function Session:_finishShot(shot,hit,miss,t,reason)
 self.diagnostics:recordShot({type="shot",weapon=shot.weapon,targetId=shot.id,hit=hit,intendedHit=hit,
  accepted=true,missDistanceStuds=if shot.mode=="Simulated" then miss else nil,flightSeconds=t-(shot.started or shot.due),reason=reason,
  spreadRadians=shot.profile.spreadRadians,scope="local laboratory",impactTime=t})
 self.lastShot=if hit then "Impacto local al blanco elegido" else "Fallo local: "..reason
end
function Session:_startShots(t)
 for i=#self.shots,1,-1 do
  local shot=self.shots[i]
  if shot.due<=t then
   if shot.profile.kind=="projectile" then
    shot.started=shot.due;shot.processed=shot.due;shot.closest=math.huge
    shot.part=self:_part("LocalProjectile",Vector3.new(0.35,0.35,0.35),Color3.fromRGB(255,198,92))
    shot.part.Shape=Enum.PartType.Ball;shot.part.Position=shot.origin
    shot.lifetime=math.min(self.config.core.maxFlightSeconds,MAX_RANGE/shot.profile.speed)
    shot.params=self:_params(false)
    table.insert(self.projectiles,shot)
   else
    local endpoint=shot.origin+shot.direction*MAX_RANGE
    local obstacle=workspace:Raycast(shot.origin,endpoint-shot.origin,self:_params(shot.mode=="Simulated"))
    if obstacle then endpoint=obstacle.Position end
    local chosen=nil;local nearest=1.1
    if shot.mode=="Simulated" then
     for _,spec in self.specs do
      local pos=positionAt(spec,shot.due)
      local fraction=Geometry.sphereIntersection(shot.origin-pos,endpoint-pos,spec.radius)
      if fraction and fraction<nearest then nearest=fraction;chosen=spec end
     end
    end
    local position=if shot.target.spec then positionAt(shot.target.spec,shot.due) else shot.target.current
    local _,closest=Geometry.closestOnSegment(position,shot.origin,endpoint)
    local hit=if shot.mode=="Simulated" then chosen and chosen.id==shot.id
      else obstacle and shot.target.model and obstacle.Instance:IsDescendantOf(shot.target.model)
    if chosen then endpoint=shot.origin+(endpoint-shot.origin)*nearest end
    self:_trace(shot.origin,endpoint,t)
    self:_finishShot(shot,hit==true,math.max(0,(position-closest).Magnitude-shot.target.radius),shot.due,
     if hit then "local-hit" elseif obstacle then "obstacle" else "miss")
   end
   table.remove(self.shots,i)
  end
 end
end
local function projectilePosition(shot,t)
 local dt=t-shot.started
 return shot.origin+shot.direction*(shot.profile.speed*dt)+Vector3.new(0,-0.5*shot.profile.gravity*dt*dt,0)
end
function Session:_advanceShots(t)
 for i=#self.projectiles,1,-1 do
  local shot=self.projectiles[i];local finished=false
  local endTime=math.min(t,shot.started+shot.lifetime);local steps=0
  while shot.processed<endTime and steps<64 do
   steps+=1
   local aTime=shot.processed;local bTime=math.min(aTime+1/120,endTime)
   local a=projectilePosition(shot,aTime);local b=projectilePosition(shot,bTime)
   local startPos=if shot.target.spec then positionAt(shot.target.spec,aTime) else shot.target.current
   local endPos=if shot.target.spec then positionAt(shot.target.spec,bTime) else shot.target.current
   local delta=b-a
   local obstacle=if delta.Magnitude>1e-8 then
    (if shot.profile.radius>0 then workspace:Spherecast(a,shot.profile.radius,delta,shot.params)
     else workspace:Raycast(a,delta,shot.params)) else nil
   local fraction,closest=Geometry.closestOnSegment(Vector3.zero,a-startPos,b-endPos)
   local contact,hitTargetId=nil,nil
   if shot.mode=="Simulated" then
    for _,spec in self.specs do
     local pa=positionAt(spec,aTime);local pb=positionAt(spec,bTime)
     local candidate=Geometry.sphereIntersection(a-pa,b-pb,spec.radius+shot.profile.radius)
     if candidate and (not contact or candidate<contact) then contact=candidate;hitTargetId=spec.id end
    end
   end
   local obstacleFraction=if obstacle then obstacle.Distance/delta.Magnitude else 1.1
   local stop=math.min(1,contact or 1.1,obstacleFraction)
   fraction=math.min(fraction,stop)
   closest=(a-startPos):Lerp(b-endPos,fraction)
   shot.closest=math.min(shot.closest,math.max(0,closest.Magnitude-shot.target.radius-shot.profile.radius))
   if obstacle and obstacleFraction<=(contact or 1.1) then
    local hit=shot.mode=="OwnCharacters" and shot.target.model and obstacle.Instance:IsDescendantOf(shot.target.model)
    self:_finishShot(shot,hit==true,shot.closest,aTime+(bTime-aTime)*stop,if hit then "local-hit" else "obstacle")
    finished=true;break
   elseif contact then
    local hit=hitTargetId==shot.id
    self:_finishShot(shot,hit,if hit then 0 else shot.closest,aTime+(bTime-aTime)*contact,if hit then "local-hit" else "other-target")
    finished=true;break
   end
   shot.processed=bTime;shot.part.Position=b
  end
  if not finished and shot.processed>=shot.started+shot.lifetime then
   self:_finishShot(shot,false,shot.closest,shot.processed,"flight-limit");finished=true
  end
  if finished then shot.part:Destroy();table.remove(self.projectiles,i) end
 end
end
function Session:_metrics()
 local result=self.solution;local target=self.selected and self.targets[self.selected]
 local range=if result then result.range else "close"
 local calibration=self.calibration:summary(self.config.activeProfile,range,now())
 local stats=self.diagnostics:summary()
 local live={rtt=if self.rtt then string.format("%.1f ms (%s)",self.rtt*1000,if self.config.useSimulatedPing then "simulado" else "motor") else "No disponible",
  ping=string.format("%.1f / %.1f ms",self.predictor.latency.raw*1000,self.predictor.latency.smoothed*1000),
  delay="—",speed="—",distance="—",range=range,current="—",predicted="—",aimpoint="—",error=if self.lastError then string.format("%.3f studs",self.lastError) else "Sin verdad medida",
  status=if self.config.targetMode=="Simulated" then "SIMULACIÓN LOCAL · referencia conocida" else "OBSERVACIÓN LOCAL · sin verdad autoritativa",
  target=self.selected or "Sin blanco",weapon=self.config.activeProfile,flight="—",
  autoRMSE=if calibration.autoCount>0 then string.format("%.3f studs (%d)",calibration.autoRMSEStuds,calibration.autoCount) else "Sin muestras",
  manualRMSE=if calibration.manualCount>0 then string.format("%.3f studs (%d)",calibration.manualRMSEStuds,calibration.manualCount) else "Sin muestras",
  measurementCount=tostring(stats.predictionCount),hitRate=string.format("%.1f%% (%d tiros locales)",stats.hitRate*100,stats.shots),
  suggestion=string.format("%+.1f ms (%d válidas)",calibration.suggestedOffsetSeconds*1000,calibration.confidenceSamples)}
 if result then
  live.delay=string.format("%.1f ms",result.delaySeconds*1000);live.speed=string.format("%.1f studs/s",result.velocity.Magnitude)
  live.distance=string.format("%.1f studs",result.distanceStuds);live.flight=string.format("%.3f s",result.flightSeconds)
  live.predicted=string.format("%.1f, %.1f, %.1f",result.targetPosition.X,result.targetPosition.Y,result.targetPosition.Z)
  live.aimpoint=string.format("%.1f, %.1f, %.1f",result.position.X,result.position.Y,result.position.Z)
 end
 if target then local p=target.sample.position;live.current=string.format("%.1f, %.1f, %.1f",p.X,p.Y,p.Z) end
 if self.compatibility and #self.compatibility.warnings>0 then live.status ..= " · " .. table.concat(self.compatibility.warnings," ") end
 self.ui:update(live)
end
function Session:step(dt,t)
 if self.destroyed then return end
 self:_ping(t);self:_measure(t);self:_startShots(t);self:_advanceShots(t)
 for i=#self.effects,1,-1 do if self.effects[i].due<=t then self.effects[i].part:Destroy();table.remove(self.effects,i) end end
 self.observeAccumulator+=dt;self.measureAccumulator+=dt;self.uiAccumulator+=dt
 if self.observeAccumulator>=1/self.config.core.updateHz then
  self.observeAccumulator%=1/self.config.core.updateHz;self:_observe(t);self:_select(t)
 end
 if self.measureAccumulator>=MEASUREMENT_INTERVAL then self.measureAccumulator%=MEASUREMENT_INTERVAL;self:_queueMeasurements(t) end
 if self.config.adaptiveCalibration and t-self.lastCalibration>=1 then
  self.lastCalibration=t;self:_applyCalibration(true,t)
 end
 if self.uiAccumulator>=0.1 then self.uiAccumulator%=0.1;self:_metrics() end
 local solution=self.solution;local camera=workspace.CurrentCamera
 if self.selectionRing then
  self.selectionRing.Visible=self.config.core.enabled
  self.selectionRing.Position=UDim2.fromOffset(self.selectionMouse.X,self.selectionMouse.Y)
  self.selectionRing.Size=UDim2.fromOffset(self.config.core.fovPixels*2,self.config.core.fovPixels*2)
 end
 local visible=self.config.core.enabled and self.config.core.debugVisualization and solution~=nil
 self.currentMarker.Transparency=if visible then 0.5 else 1
 self.predictedMarker.Transparency=if visible then 0.2 else 1
 if solution then
  local tau=self.config.predictionSmoothingSeconds
  local alpha=if tau>0 then 1-math.exp(-dt/tau) else 1
  self.drawPoint=if self.drawPoint then self.drawPoint:Lerp(solution.position,alpha) else solution.position
  self.predictedMarker.Position=self.drawPoint
  local target=self.targets[self.selected]
  if target then self.currentMarker.Position=target.current end
  if self.rightMouse and self.config.core.enabled and camera and not self.ui:isPointerOver() and not self.services.UserInputService:GetFocusedTextBox() then
   local desired=CFrame.lookAt(camera.CFrame.Position,self.drawPoint)
   camera.CFrame=camera.CFrame:Lerp(desired,1-math.exp(-dt/math.max(0.01,tau)))
  end
 end
end
function Session:destroy()
 if self.destroyed then return end
 self.destroyed=true;self.rightMouse=false
 for _,c in self.connections do c:Disconnect() end
 table.clear(self.connections);table.clear(self.pending);table.clear(self.shots);table.clear(self.projectiles);table.clear(self.effects)
 if self.predictor then self.predictor:clear() end
 if self.diagnostics then self.diagnostics:clear() end
 if self.calibration then self.calibration:clear() end
 if self.ui then self.ui:destroy() end
 if self.world then self.world:Destroy() end
end
function Session.init(options)
 options=options or {}
 local compatibility=Runtime.check()
 assert(compatibility.ready,Runtime.errorMessage(compatibility))
 local run=compatibility.services.RunService
 local players=compatibility.services.Players;local player=compatibility.player
 local config,message
 if options.configuration then config,message=Configuration.import(options.configuration) else config=Configuration.new() end
 assert(config,message or "Configuración inválida")
 local pg=compatibility.playerGui
 local previous=pg:FindFirstChild("DHPredictionLab")
 local self=setmetatable({config=config,player=player,compatibility=compatibility,connections={},specs={},pending={},shots={},projectiles={},effects={},
  diagnostics=Diagnostics.new(600),calibration=Calibration.new(),destroyed=false,paused=false,rightMouse=false,
  actualOneWay=0,rtt=nil,nextFire=0,lastCalibration=-math.huge,observeAccumulator=0,measureAccumulator=0,uiAccumulator=0,
  selectionMouse=game:GetService("UserInputService"):GetMouseLocation(),random=Random.new(),
  services={Players=players,UserInputService=game:GetService("UserInputService"),GuiService=game:GetService("GuiService"),HttpService=game:GetService("HttpService")}},Session)
 local built,failure=pcall(function()
 self:_newPredictors()
 self.world=Instance.new("Folder");self.world.Name="DHPredictionLabLocal";self.world.Parent=workspace
 self.currentMarker=self:_part("CurrentPosition",Vector3.new(0.5,0.5,0.5),Color3.fromRGB(89,215,214));self.currentMarker.Shape=Enum.PartType.Ball;self.currentMarker.Transparency=1
 self.predictedMarker=self:_part("PredictedPosition",Vector3.new(0.65,0.65,0.65),Color3.fromRGB(73,148,255));self.predictedMarker.Shape=Enum.PartType.Ball;self.predictedMarker.Transparency=1
 self.ui=Interface.new(config,{
  onChange=function(path,value) return self:_change(path,value) end,
  onFire=function() self:fire() end,
  onApplyCalibration=function() return self:_applyCalibration(false,now()) end,
  onSave=function()
   local envelope,msg=Configuration.toEnvelope(self.config)
   if not envelope then return nil,msg end
   return self.services.HttpService:JSONEncode(envelope)
  end,
  onLoad=function(text)
   if #text>65536 then return false,"JSON supera 64 KiB" end
   local ok,decoded=pcall(function() return self.services.HttpService:JSONDecode(text) end)
   if not ok then return false,"JSON inválido" end
   local loaded,msg=Configuration.fromEnvelope(decoded)
   if not loaded then return false,msg end
   self:_replaceConfig(loaded);return true
  end,
  onReset=function() self:_replaceConfig(Configuration.new());self.ui:setStatus("Defaults restaurados") end,
  onUnload=function() self:destroy() end,
  onClearMeasurements=function()
   self:_clearMeasurements()
   self.ui:setStatus("Nueva ventana de medición")
  end,
  onExportMeasurements=function()
   local records={}
   table.insert(records,self.services.HttpService:JSONEncode({configuration=Configuration.toEnvelope(self.config),summary=self.diagnostics:summary(),scope="local laboratory"}))
   for _,record in self.diagnostics.predictions do table.insert(records,self.services.HttpService:JSONEncode(record)) end
   for _,record in self.diagnostics.shots do table.insert(records,self.services.HttpService:JSONEncode(record)) end
   return table.concat(records,"\n")
  end,
 })
 self.selectionRing=Instance.new("Frame");self.selectionRing.Name="SelectionFOV"
 self.selectionRing.BackgroundTransparency=1;self.selectionRing.AnchorPoint=Vector2.new(0.5,0.5)
 self.selectionRing.ZIndex=0;self.selectionRing.Parent=self.ui.gui
 local round=Instance.new("UICorner");round.CornerRadius=UDim.new(1,0);round.Parent=self.selectionRing
 local outline=Instance.new("UIStroke");outline.Color=Color3.fromRGB(69,139,245);outline.Thickness=1
 outline.Transparency=0.55;outline.Parent=self.selectionRing
 local stop=self.ui.gui:FindFirstChild("DHPredictionLabStop")
 if stop then connection(self,stop.Event,function() self:destroy() end) end
 connection(self,self.ui.gui.Destroying,function() self:destroy() end)
 local ownerOK,owner=pcall(function()
  return script and script:IsA("LocalScript") and script.Destroying or nil
 end)
 if ownerOK and owner then connection(self,owner,function() self:destroy() end) end
 connection(self,self.services.UserInputService.InputBegan,function(input,processed)
  if processed or self.services.UserInputService:GetFocusedTextBox() or self.ui:isPointerOver() then return end
  if input.UserInputType==Enum.UserInputType.MouseButton2 then self.rightMouse=true
  elseif input.KeyCode==Enum.KeyCode.F then self:fire() end
 end)
 connection(self,self.services.UserInputService.InputEnded,function(input)
  if input.UserInputType==Enum.UserInputType.MouseButton2 then self.rightMouse=false end
 end)
 connection(self,self.services.UserInputService.WindowFocusReleased,function() self.rightMouse=false end)
 connection(self,run.RenderStepped,function(dt)
  if self.destroyed or self.paused then return end
  local ok,message=pcall(function() self:step(dt,now()) end)
  if not ok then
   self.paused=true;self.rightMouse=false
   local text="Pausado por incompatibilidad: "..tostring(message)..". Revisa el cliente o usa Unload."
   -- Avoid repeating the layout/camera operation that may have failed. A fault
   -- while displaying the error must not escape or restart frame updates.
   pcall(function()
    self.currentMarker.Transparency=1;self.predictedMarker.Transparency=1;self.selectionRing.Visible=false
    self.ui:setStatus(text,true)
    for _,label in self.ui.metrics.status or {} do label.Text=text end
   end)
   Runtime.reportFailure(text)
  end
 end)
 self.ui:setStatus("Laboratorio local listo · F dispara · RMB orienta cámara")
 end)
 if not built then self:destroy();error("Inicialización: "..tostring(failure),2) end
 -- Commit ownership only after a complete constructor; failed builds leave the
 -- existing session usable, and remove their own partial objects/connections.
 if previous then
  local stop=previous:FindFirstChild("DHPredictionLabStop")
  if stop and stop:IsA("BindableEvent") then stop:Fire() end
  previous:Destroy()
 end
 return self
end
return Session
