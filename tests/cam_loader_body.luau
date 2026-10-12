--!nonstrict
-- Actual published loader text and actual Cam payload, with explicit doubles.
return function(payload,loader)
 local Mock=require("./CamMock")
 local tests,checks=0,0
 local function check(value,message) checks+=1;assert(value,message) end
 local function test(name,body)
  tests+=1
  local ok,err=pcall(body);assert(ok,name..": "..tostring(err))
 end
 local function execute(mock)
  local hostLoadstring=loadstring
  mock.env.loadstring=function(code,name)
   local chunk,err=hostLoadstring(code,name)
   if chunk then setfenv(chunk,mock.env) end
   return chunk,err
  end
  local chunk=assert(hostLoadstring(loader,"SEDWARE.CamLoaderTest"))
  setfenv(chunk,mock.env);return chunk()
 end
 test("loader downloads exact fixed-commit Cam variant and initializes it",function()
  local mock=Mock.new();mock.env.SEDWARE_CAM_NO_AUTOSTART=false
  function mock.env.game:HttpGet(url)
   local commit=string.match(url,"^https://raw%.githubusercontent%.com/sedonkkk/sedon%-/([%da-f]+)/SedwareCamLock%.lua$")
   check(commit and #commit==40,"Loader must identify the real fixed-commit Cam artifact")
   return payload
  end
  local api=execute(mock)
  check(api.session and api.session.active and not api.session.config.Enabled)
  check(mock:hasLog("[SEDWARE][CamLoader][START]"))
  api.Unload();check(mock:countConnections()==0 and mock:countRenderBindings()==0)
 end)
 test("HTTP failure exposes its cause without creating a session",function()
  local mock=Mock.new()
  function mock.env.game:HttpGet() error("controlled Cam HTTP failure") end
  local ok,err=pcall(execute,mock)
  check(not ok and string.find(tostring(err),"controlled Cam HTTP failure",1,true)~=nil)
  check(mock:countConnections()==0 and mock:countRenderBindings()==0)
 end)
 test("compilation failure identifies the phase",function()
  local mock=Mock.new()
  function mock.env.game:HttpGet() return "this is not valid code" end
  local ok,err=pcall(execute,mock)
  check(not ok and string.find(tostring(err),"COMPILE FAIL",1,true)~=nil)
  check(mock:countConnections()==0 and mock:countRenderBindings()==0)
 end)
 print("CAM loader doubles: "..tests.." tests, "..checks.." assertions, 0 failures")
end
