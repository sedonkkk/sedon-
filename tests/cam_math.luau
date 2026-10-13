--!nonstrict
-- Official Luau CLI regression tests: numerical and configuration behavior.
-- These do not substitute for native Studio camera/renderer verification.
local V=require("./Vector")
local Config=require("../src/cam/Config")
local PredictionEngine=require("../src/cam/PredictionEngine")
local zero=V.new(0,0,0)
local tests,checks,failures=0,0,0
local function check(condition,message)
 checks+=1
 assert(condition,message or "assertion failed")
end
local function near(actual,expected,tolerance)
 check(type(actual)=="number" and actual==actual and math.abs(actual-expected)<=(tolerance or 1e-9),
  "expected "..tostring(expected)..", got "..tostring(actual))
end
local function vectorNear(actual,expected,tolerance)
 check(actual~=nil and (actual-expected).Magnitude<=(tolerance or 1e-8),
  "expected "..tostring(expected)..", got "..tostring(actual))
end
local function test(name,body)
 tests+=1
 local ok,message=pcall(body)
 if not ok then failures+=1;print("FAIL "..name..": "..tostring(message)) end
end
local function configuration(overrides)
 local config,message=Config.new(overrides)
 check(config~=nil,message)
 return config
end
local function moving(overrides)
 -- These fixtures isolate calibrated velocity * horizon arithmetic. The V3.1
 -- vertical/reversal guards have separate default-behavior regressions.
 local input={Enabled=true,MemoryTracking=false,VerticalControl=false,ReversalDamping=false}
 for key,value in overrides or {} do
  input[key]=if key=="PredictionX" then value*13.15/0.1205 elseif key=="PredictionY" then value*13.15/0.08 else value
 end
 local engine=PredictionEngine.new(configuration(input))
 check(engine:observe(0,zero,"Running"))
 check(engine:observe(0.1,V.new(1,2,3),"Running"))
 return engine
end

test("standalone header and independent defaults match V3.1 controls",function()
 local a,b=Config.defaults(),Config.defaults()
 check(not a.Enabled and a.HitPart=="UpperTorso")
 check(a.CamPrediction==nil);near(a.PredictionX,13.15);near(a.PredictionY,13.15)
 near(a.Smoothness,0.405);near(a.Radius,180)
 near(a.PredictionSmoothing,0);near(a.VelocitySmoothing,0.06)
 check(a.MemoryTracking and a.VelocityPrediction and a.PingCompensation)
 check(a.FallbackR6 and a.RespectScriptableCamera)
 check(a.VerticalControl and a.ReversalDamping and not a.ReacquireOnLoss)
 near(a.TargetPartGraceSeconds,0.15)
 check(#Config.controls==17)
 for _,control in Config.controls do
  check(Config.fields[control.key]==control and a[control.key]~=nil)
 end
 local header=assert(loadstring("return "..Config.sourceLiteral))()
 local parsed=configuration(header)
 for key,value in a do
  if type(value)~="table" then check(parsed[key]==value,"header mismatch: "..key) end
 end
 a.PingReferences[1].X=0.01
 near(b.PingReferences[1].X,0.113)
 local input={PingReferences={{PingMs=62,X=0.12,Y=0.08}}}
 local copied=configuration(input)
 input.PingReferences[1].X=0.6
 near(copied.PingReferences[1].X,0.12)
end)

test("malformed finite bounds keys and calibration objects are rejected",function()
 local cyclic={};cyclic.self=cyclic
 local invalid={
  false,1,"Config",function() end,setmetatable({},{__index={}}),
  {Enabled="true"},{CamPrediction=0/0},{CamPrediction=math.huge},{CamPrediction=-0.1},
  {CamPrediction=69.01},{PredictionX=-0.1},{PredictionY=math.huge},{Smoothness=1.001},
  {Radius=0},{HitPart="Torso"},{Unknown=true},{LockKey="DefinitelyNotAKey"},
  {LockKey={Name="C"}},{HistoryCapacity=2.5},{MinPredictionX=0.4,MaxPredictionX=0.3},
  {CloseDistance=120,MediumDistance=40},{PingReferences={}},
  {PingReferences={[2]={PingMs=62,X=0.12,Y=0.08}}},
  {PingReferences={{PingMs=62,X=0.12,Y=0.08},{PingMs=55,X=0.1,Y=0.07}}},
  {PingReferences={{PingMs=62,X=0.12,Y=0.08,Extra=1}}},
  {PingReferences={{PingMs=62,X=0.12,Y=cyclic}}},
  {PingReferences={{PingMs=62,X=0.12,Y=0.08},{PingMs=62,X=0.13,Y=0.08}}},
 }
 for index,input in invalid do
  local ok,config,message=pcall(Config.new,input)
  check(ok and config==nil and type(message)=="string","invalid input escaped validation: "..index)
 end
 local sparse={Enabled=true}
 check(not Config.validate(sparse))
 check(Config.validate(configuration()))
end)

test("direct X/Z and Y seconds have no hidden gain",function()
 local output=moving():predict(zero,0.1)
 check(output~=nil and output.camGain==nil and output.camPrediction==nil)
 near(output.predictionX,0.1205);near(output.predictionY,0.08)
 check(output.predictionUnits=="seconds")
 vectorNear(output.rawPosition,V.new(1+10*0.1205,2+20*0.08,3+30*0.1205))
 check(output.physicsVerified==false and output.flightSeconds==0)
end)

test("zero manual horizons retain only actual observation age",function()
 for _,values in {{0,0},{0.1,0.04},{0.2,0.03}} do
  local output=moving({PredictionX=values[1],PredictionY=values[2]}):predict(zero,0.15)
  near(output.predictionX,values[1]);near(output.predictionY,values[2]);near(output.ageSeconds,0.05)
  vectorNear(output.rawPosition,V.new(1+10*(values[1]+0.05),2+20*(values[2]+0.05),3+30*(values[1]+0.05)))
 end
 check(Config.new({CamPrediction=13.8})==nil,"removed multiplier was still accepted")
end)

test("axis edits are independent and adjusted horizons remain bounded",function()
 local engine=moving({PredictionX=0.2,PredictionY=0.03})
 local output=engine:predict(zero,0.1)
 vectorNear(output.rawPosition,V.new(3,2.6,9))
 engine=moving({PredictionX=0.6,PredictionY=0.6,CloseOffset=0.2})
 output=engine:predict(zero,0.1)
 near(output.predictionX,0.35);near(output.predictionY,0.35)
 vectorNear(output.rawPosition,V.new(4.5,9,13.5))
end)

test("memory reversals and jump state changes rebase without slow trailing velocity",function()
 local engine=PredictionEngine.new(configuration({Enabled=true,VerticalControl=false,ReversalDamping=false}))
 check(engine:observe(0,zero,"Running"))
 check(engine:observe(0.1,V.new(1,0,0),"Running"))
 local resets=engine.history.resets
 check(engine:observe(0.2,V.new(0,0,0),"Running"))
 near(engine.history.resets,resets+1)
 vectorNear(engine.history.velocity,V.new(-10,0,0))
 vectorNear(engine:predict(zero,0.2).position,V.new(-1.205,0,0))
 resets=engine.history.resets
 check(engine:observe(0.3,V.new(-1,3,0),"Jumping"))
 near(engine.history.resets,resets+1)
 vectorNear(engine.history.velocity,V.new(-10,30,0))
 vectorNear(engine.history.acceleration,zero)
 vectorNear(engine:predict(zero,0.3).position,V.new(-2.205,5.4,0))
end)

test("Memory history stays bounded and converges under sustained tracking",function()
 local engine=PredictionEngine.new(configuration({Enabled=true,HistoryCapacity=5,HistoryWindow=0.12}))
 for index=0,240 do
  local time=index/120
  check(engine:observe(time,V.new(12*time,0,-8*time),"Running"))
  check(#engine.history.samples<=5)
 end
 vectorNear(engine.history.velocity,V.new(12,0,-8),1e-8)
 vectorNear(engine:predict(zero,2).position,V.new(24+12*0.1205,0,-16-8*0.1205),1e-8)
end)

test("invalid observations ping and time cannot corrupt the accepted stream",function()
 local engine=moving()
 check(engine:samplePing(0.062,0))
 local latest=engine.history:latest()
 for _,position in {{},V.new(math.huge,0,0),V.new(0/0,0,0)} do
  check(not engine:observe(0.2,position,"Running"))
 end
 check(not engine:observe(0.1,zero,"Running"))
 check(not engine:observe(0.2,zero,{}))
 check(engine.history:latest()==latest)
 for _,bad in {0/0,math.huge,-0.01,3} do check(not engine:samplePing(bad,0.1)) end
 check(not engine:samplePing(0.07,-0.1))
 near(engine:predict(zero,0.1).rawPingMs,62)
 check(engine:predict({},0.1)==nil)
 check(engine:predict(zero,0/0)==nil)
 check(engine:predict(zero,0.701)==nil)
 check(engine:predict(zero,0.049)==nil)
 check(engine:predict(V.new(-400,0,0),0.1)==nil)
end)

test("numeric control updates preserve motion and ping and apply on next prediction",function()
 local engine=moving({MemoryTracking=true})
 check(engine:samplePing(0.062,0))
 local history,latest,latency=engine.history,engine.history:latest(),engine.latency
 local velocity=history.velocity
 local config=configuration(engine.config)
 for _,edit in {{"FlySpeed",80},{"PredictionX",0.1},{"PredictionY",0.04},{"Smoothness",0.9},{"Radius",120}} do
  check(Config.updateField(config,edit[1],if edit[1]=="PredictionX" then edit[2]*13.15/0.1205 elseif edit[1]=="PredictionY" then edit[2]*13.15/0.08 else edit[2]))
  check(engine:updateConfig(config))
  check(engine.history==history and engine.history:latest()==latest and engine.latency==latency)
  vectorNear(engine.history.velocity,velocity)
 end
 local output=engine:predict(zero,0.1)
 near(output.predictionX,0.1);near(output.predictionY,0.04);near(output.rawPingMs,62)
 vectorNear(output.position,V.new(1+velocity.X*0.1,2+velocity.Y*0.04,3+velocity.Z*0.1))
 local beforeX=config.PredictionX
 check(not Config.updateField(config,"PredictionX",0/0))
 near(config.PredictionX,beforeX)
 local bad=table.clone(config);bad.PredictionX=-1
 check(not engine:updateConfig(bad))
 check(engine.history==history and engine.config.PredictionX==beforeX)
 check(Config.updateField(config,"Enabled",false));check(engine:updateConfig(config))
 check(engine:predict(zero,0.1)==nil and engine.history==history)
 check(Config.updateField(config,"Enabled",true));check(engine:updateConfig(config))
 check(engine:predict(zero,0.1)~=nil and engine.history==history)
end)

test("changing Hit Part resets the position stream while preserving usable ping",function()
 local engine=moving({AutoPrediction=true})
 check(engine:samplePing(0.062,0))
 local history,latency=engine.history,engine.latency
 local nextConfig=configuration(engine.config)
 check(Config.updateField(nextConfig,"HitPart","Head"))
 check(engine:updateConfig(nextConfig))
 check(engine.history~=history and engine.history:latest()==nil)
 check(engine.latency==latency and engine:predict(zero,0.1)==nil)
 check(engine:observe(0.2,V.new(5,7,9),"Running"))
 local output=engine:predict(zero,0.2)
 check(output.hitPart=="Head" and output.status=="Auto")
 near(output.rawPingMs,62)
 vectorNear(output.position,V.new(5,7,9))
end)

test("Auto consumes the direct total curve without adding ping twice",function()
 for _,point in {{55,0.113,0.075},{62,0.120,0.080},{70,0.128,0.085}} do
  local engine=moving({AutoPrediction=true})
  check(engine:samplePing(point[1]/1000,0))
  local output=engine:predict(zero,0.15)
  check(output.status=="Auto")
  near(output.predictionX,point[2]);near(output.predictionY,point[3]);near(output.rawPingMs,point[1])
  vectorNear(output.position,V.new(1+10*(point[2]+0.05),2+20*(point[3]+0.05),3+30*(point[2]+0.05)))
 end
 local midpoint=moving({AutoPrediction=true});check(midpoint:samplePing(0.0585,0))
 near(midpoint:predict(zero,0.1).predictionX,0.1165)
 near(midpoint:predict(zero,0.1).predictionY,0.0775)
end)

test("Auto missing ping uses manual fallback and reset clears all state",function()
 local engine=moving({AutoPrediction=true})
 local output=engine:predict(zero,0.1)
 check(output.status=="AutoFallback")
 near(output.predictionX,0.1205);near(output.predictionY,0.08)
 check(engine:samplePing(0.07,0))
 check(engine:predict(zero,0.1).status=="Auto")
 check(engine:samplePing(nil,0.1))
 check(engine:predict(zero,0.1).status=="AutoFallback")
 check(engine:samplePing(0.07,0.2))
 engine:reset()
 check(engine.history:latest()==nil and engine:predict(zero,0.3)==nil)
 check(engine:observe(0.3,V.new(3,0,0),"Running"))
 output=engine:predict(zero,0.3)
 check(output.status=="AutoFallback" and output.rawPingMs==nil)
end)

test("ping smoothing remains based on elapsed time at different sampling rates",function()
 local function run(hz)
  local engine=PredictionEngine.new(configuration({Enabled=true,AutoPrediction=true,MemoryTracking=false}))
  check(engine:samplePing(0.055,0))
  for index=1,hz do check(engine:samplePing(0.070,index/hz)) end
  check(engine:observe(0.9,V.new(9,0,0),"Running"))
  check(engine:observe(1,V.new(10,0,0),"Running"))
  return engine:predict(zero,1)
 end
 local a,b=run(100),run(10)
 local expected=70+(55-70)*math.exp(-1/0.8)
 near(a.smoothedPingMs,expected,1e-10);near(b.smoothedPingMs,expected,1e-10)
 near(a.predictionX,b.predictionX,1e-12);near(a.predictionY,b.predictionY,1e-12)
end)

print(string.format("SEDWARE CAM prediction: %d tests, %d assertions, %d failures",tests,checks,failures))
assert(failures==0,"SEDWARE CAM numerical regression tests failed")
