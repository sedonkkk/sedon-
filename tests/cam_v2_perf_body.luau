--!nonstrict
-- Host Luau CPU measurements with simulated players/API doubles. No Roblox FPS
-- or native rendering/physics result is produced by this benchmark.
return function(reloadBundle)
 local Mock=require("./CamV2Mock")
 local tests,checks=0,0
 local function check(value,message) checks+=1;assert(value,message or "ESP benchmark invariant failed") end
 for _,players in {5,15,30} do
  tests+=1
  local mock=Mock.new()
  for index=1,players do mock:addPlayer("BenchmarkFixture"..index,mock.env.Vector3.new(index,0,-50)) end
  local api=reloadBundle(mock.env)
  local session=api.init({ESP=true,Hitboxes=true,Names=true,DebugMode=true})
  mock:advance(0.30)
  check(session.esp.stats.visible==players)
  check(session.esp.stats.created==players*3,"unexpected indicator instance count")
  local initialCreated=session.esp.stats.created
  local initialConnections=mock:countConnections()
  mock:resetCounters()
  -- Use the actual CLI monotonic clock only for CPU cost, after startup.
  mock.env.os.clock=os.clock
  local iterations=1000;local elapsed=0
  local started=os.clock()
  for index=1,iterations do
   session.esp:update(mock:getTime()+index*0.11)
   elapsed+=session.esp.stats.lastSeconds
  end
  local total=os.clock()-started
  check(session.esp.stats.created==initialCreated,"ESP allocated indicators each update")
  check(mock.counters.candidateScans==0,"ESP rescanned Players:GetPlayers")
  check(mock:countConnections()==initialConnections,"ESP accumulated connections")
  for _,hz in {30,60,144} do
   session.esp.nextUpdate=nil
   local before=session.esp.stats.updates
   for index=1,hz*2 do session.esp:update(2000+index/hz) end
   local updates=session.esp.stats.updates-before
   check(updates>=15 and updates<=21,"ESP cadence changed excessively with scheduled FPS")
  end
  session:configure("ESP",false)
  check(mock:liveInstances("SelectionBox")==0 and mock:liveInstances("BillboardGui")==0)
  api.Unload()
  check(mock:countConnections()==0 and mock:countRenderBindings()==0 and mock.tweens.active==0,"benchmark cleanup leaked")
  print(string.format("V2 ESP CLI simulated: players=%d updates=%d meanUpdateMs=%.6f maxUpdateMs=%.6f loopMs=%.3f instances=%d",players,
   iterations,elapsed/iterations*1000,session.esp.stats.maxSeconds*1000,total*1000,initialCreated))
 end
 print(string.format("V2 ESP performance doubles: %d tests, %d assertions, 0 failures",tests,checks))
end
