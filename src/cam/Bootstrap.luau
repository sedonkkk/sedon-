--!nonstrict
local Runtime=if script then require(script.Parent.Parent.pink.Runtime) else require("../pink/Runtime")
local Bootstrap={}
function Bootstrap.new(initialConfig,getModule,moduleNames,headerError)
 local API={Config=initialConfig,getModule=getModule,Modules=setmetatable({}, {__index=function(_,name) return getModule(name) end})}
 local generation=0
 function API.checkCompatibility(options) return Runtime.check(options or initialConfig) end
 function API.tryInit(options)
  generation+=1;local request=generation
  local report={ready=false,missing={},pending={},events={}}
  local phase="Modules"
  local config
  local initialized,result=xpcall(function()
   for _,name in moduleNames do getModule(name) end
   Runtime.trace(report,"CamModules","READY",tostring(#moduleNames).." embedded modules loaded")
   phase="Configuration"
   if options==nil and headerError then error(headerError) end
   local problem;config,problem=getModule("Config").new(if options==nil then initialConfig else options);assert(config,problem)
   Runtime.trace(report,"CamConfiguration","READY","Enabled="..tostring(config.Enabled).." HitPart="..config.HitPart)
   phase="Services"
   local audit=Runtime.check(config);audit.events=report.events
   report=Runtime.awaitReady(config,audit,function() return request~=generation end)
   if request~=generation or report.cancelled then return nil end
   assert(report.ready,Runtime.errorMessage(report))
   phase="CamSession"
   local session=getModule("Session").init(config,report)
   API.session=session
   return session
  end,Runtime.traceback)
  if request~=generation or report.cancelled then return nil,report end
  API.compatibility=report
  if initialized then return result,report end
  if not report.playerGui then
   local audited,audit=pcall(Runtime.check,config)
   if audited then report.playerGui=audit.playerGui end
  end
  report.ready=false;report.error=tostring(result);report.failurePhase=report.failurePhase or phase
  table.insert(report.missing,report.failurePhase..": "..tostring(result))
  Runtime.trace(report,report.failurePhase,"FAIL",result)
  pcall(function() getModule("Session").notifyFailure(report,result) end)
  return nil,report
 end
 function API.init(options)
  local session,report=API.tryInit(options)
  if not session then error(Runtime.errorMessage(report),2) end
  return session
 end
 function API.Unload()
  generation+=1
  local current=API.session;API.session=nil
  if current then current:destroy();return true end
  return false
 end
 for _,name in {"GetLockedTarget","GetPrediction","GetPredictedPosition","LockTarget","UnlockTarget","configure","SetEnabled","SetHitPart","ApplyESPTarget","ClearESPTarget"} do
  API[name]=function(...)
   if not API.session then return nil,"Not initialized" end
   return API.session[name](API.session,...)
  end
 end
 return API
end
return Bootstrap
