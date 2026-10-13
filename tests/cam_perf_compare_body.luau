-- Host CPU cost of actual V2/V3 bundles under the same explicit API doubles.
return function(currentSource,baselineSource)
 local Mock=require("./CamV2Mock")
 for _,players in {5,15,30} do for _,version in {"V2","V3"} do
  local m=Mock.new();local source=if version=="V2" then baselineSource else currentSource
  for i=1,players do m:addPlayer("Bench"..i,m.env.Vector3.new(i,0,-60)) end
  local chunk=assert(loadstring(source));setfenv(chunk,m.env);local api=chunk()
  local s=api.init({ESP=true,Hitboxes=true,Names=true,DebugMode=false});m:advance(.5)
  m.env.os.clock=os.clock
  for _,camEnabled in {false,true} do
   s:SetEnabled(camEnabled)
   for _,enabled in {false,true} do
   s:configure("ESP",enabled);local allocations=m:liveInstances();local connections=m:countConnections()
   local start=os.clock();for _=1,1200 do m:advance(1/60) end;local elapsed=os.clock()-start
   assert(m:liveInstances()<=allocations,"continuous visual allocation")
   assert(m:countConnections()<=connections,"connections grew")
   print(string.format("PERF,%s,%d,%s,%s,%.9f",version,players,tostring(enabled),tostring(camEnabled),elapsed/1200*1000))
  end end
  api.Unload();assert(m:countConnections()==0 and m:countRenderBindings()==0)
 end end
end
