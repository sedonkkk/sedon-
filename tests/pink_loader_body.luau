--!nonstrict
-- Exercise the actual loader and payload with explicit host/API doubles.
-- Does not execute any external host, network request or Roblox engine.
return function(payload,loader)
 local Mock=require("./PinkMock")
 local tests,checks=0,0
 local function check(value,message) checks+=1;assert(value,message) end
 local function test(name,body)
  tests+=1
  local ok,err=pcall(body)
  assert(ok,name..": "..tostring(err))
 end
 local function execute(mock)
  local hostLoadstring=loadstring
  mock.env.loadstring=function(code,name)
   local chunk,err=hostLoadstring(code,name)
   if chunk then setfenv(chunk,mock.env) end
   return chunk,err
  end
  local chunk=assert(hostLoadstring(loader,"SEDWARE.loaderTest"))
  setfenv(chunk,mock.env)
  return chunk()
 end
 test("real loader invokes the complete payload and cleans up",function()
  local mock=Mock.new()
  mock.env.PINK_DOT_NO_AUTOSTART=false
  function mock.env.game:HttpGet(url)
   local commit=string.match(url,"^https://raw%.githubusercontent%.com/sedonkkk/sedon%-/([%da-f]+)/PinkDotLock%.lua$")
   check(commit and #commit==40,"Loader must point to a fixed commit of this project")
   return payload
  end
  local api=execute(mock)
  check(api.session and api.session.active)
  check(mock:hasLog("[SEDWARE][Loader][START]"))
  api.Unload()
  check(mock:countConnections()==0)
 end)
 test("HTTP failure preserves the original cause",function()
  local mock=Mock.new()
  function mock.env.game:HttpGet() error("controlled HTTP failure") end
  local ok,err=pcall(execute,mock)
  check(not ok)
  check(string.find(tostring(err),"controlled HTTP failure",1,true)~=nil)
  check(mock:countConnections()==0)
 end)
 test("compilation failure identifies its phase",function()
  local mock=Mock.new()
  function mock.env.game:HttpGet() return "this is not valid code" end
  local ok,err=pcall(execute,mock)
  check(not ok)
  check(string.find(tostring(err),"COMPILE FAIL",1,true)~=nil)
  check(mock:countConnections()==0)
 end)
 print("SEDWARE loader doubles: "..tests.." tests, "..checks.." assertions, 0 failures")
end
