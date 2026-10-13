--!nonstrict
-- Same-host CPU comparison using the actual standalone bundles and API doubles.
-- Timesteps are scheduled at 60Hz; this does not measure Roblox FPS/rendering.
return function(currentSource,baselineSource,options)
 options=options or {}
 local Mock=require("./CamV2Mock")
 local iterations=options.iterations or 1200
 local profile=if options.far then "far" else "near"
 assert(iterations>=120 and iterations<=12000,"Benchmark iteration bound")
 local tests,checks=0,0
 local function check(value,message) checks+=1;assert(value,message) end
 print("V31_PERF_HEADER,version,players,espEnabled,camEnabled,scheduledFps,frames,meanHostFrameMs,meanSessionMs,maxSessionMs,espUpdates,projections,raycasts,candidateScans,liveInstances,createdInstances,connections,tweensActive,profile,targetZStuds")
 for _,players in {5,15,30} do for _,version in {"V3","V3.1"} do
  for _,camEnabled in {false,true} do for _,espEnabled in {false,true} do
   tests+=1
   local mock=Mock.new()
   for i=1,players do mock:addPlayer("PerformanceFixture"..i,mock.env.Vector3.new(i,0,if options.far then -800 else -60)) end
   local source=if version=="V3" then baselineSource else currentSource
   local chunk=assert(loadstring(source,"Performance."..version));setfenv(chunk,mock.env)
   local api=chunk()
   local config={Enabled=false,ESP=false,Hitboxes=true,Names=true,DebugMode=false}
   if options.far then config.MaxDistance=1500;config.ESPMaxDistance=1500 end
   local session=api.init(config)
   check(session~=nil and session.active==true,"Benchmark session failed to initialize")
   check(session:SetEnabled(camEnabled)==true,"Cam toggle rejected")
   check(session:configure("ESP",espEnabled)==true,"ESP toggle rejected")
   -- Finish toggle tweens and allocate the persistent indicator pool before
   -- timing. These fixtures remain alive, visible and stationary throughout.
   for _=1,24 do mock:advance(1/60) end
   check(mock.tweens.active==0,"Toggle tween did not finish during warmup")
   if camEnabled then check(session.locked~=nil,"Cam ON benchmark has no locked target") end
   if espEnabled then
    check(session.esp.stats.visible==players,"ESP fixture not visible")
    check(next(session.esp.renderers)~=nil,"ESP ON benchmark has no indicator pool")
   else check(next(session.esp.renderers)==nil,"ESP OFF retained indicator pool") end
   local initialLive,initialAllocated=mock:liveInstances(),#mock.instances
   local initialConnections=mock:countConnections()
   local initialESPCreated,initialESPUpdates=session.esp.stats.created,session.esp.stats.updates
   mock:resetCounters()
   -- Runtime simulation still uses GetServerTimeNow. Only host-cost timers
   -- switch to the CLI monotonic CPU clock after readiness and warmup.
   mock.env.os.clock=os.clock
   local sessionTotal,sessionMax=0,0
   local started=os.clock()
   for _=1,iterations do
    mock:advance(1/60)
    local measured=session.updateSeconds or 0
    sessionTotal+=measured;sessionMax=math.max(sessionMax,measured)
   end
   local total=os.clock()-started
   check(mock:liveInstances()<=initialLive,"Live instances grew during steady benchmark")
   check(#mock.instances==initialAllocated,"Indicator instances allocated per frame")
   check(session.esp.stats.created==initialESPCreated,"Indicator pool grew during steady benchmark")
   check(mock:countConnections()<=initialConnections,"Connections grew during steady benchmark")
   check(mock.counters.candidateScans==0,"Players:GetPlayers rescanned during benchmark")
   check(mock.tweens.active==0,"Benchmark accumulated tweens")
   print(string.format("V31_PERF,%s,%d,%s,%s,60,%d,%.9f,%.9f,%.9f,%d,%d,%d,%d,%d,%d,%d,%d,%s,%d",
    version,players,tostring(espEnabled),tostring(camEnabled),iterations,total/iterations*1000,
    sessionTotal/iterations*1000,sessionMax*1000,session.esp.stats.updates-initialESPUpdates,
    mock.counters.projections,mock.counters.raycasts,mock.counters.candidateScans,
    mock:liveInstances(),#mock.instances,mock:countConnections(),mock.tweens.active,profile,if options.far then -800 else -60))
   api.Unload()
   check(mock:countConnections()==0,"Benchmark client connections leaked after Unload")
   check(mock:countRenderBindings()==0,"Benchmark render binding leaked after Unload")
   check(mock.tweens.active==0,"Benchmark tween leaked after Unload")
  end end
 end end
 print(string.format("V31 PERF SUMMARY: %d configurations, %d invariant assertions, %d scheduled frames; host CPU / API doubles only",tests,checks,tests*iterations))
 return {configurations=tests,assertions=checks,scheduledFrames=tests*iterations}
end
