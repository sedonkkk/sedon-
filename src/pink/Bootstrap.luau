--!nonstrict
-- Protected startup orchestration. Runtime owns readiness; Session owns resources.
local Runtime = if script then require(script.Parent.Runtime) else require("./Runtime")
local Bootstrap = {}

function Bootstrap.new(initialConfig,getModule,moduleNames,headerError)
 local API={Config=initialConfig,getModule=getModule}
 API.Modules=setmetatable({}, {__index=function(_,name) return getModule(name) end})
 local generation=0
 function API.checkCompatibility(options)
  return Runtime.check(options or initialConfig)
 end
 function API.tryInit(options)
  generation+=1
  local request=generation
  local report={ready=false,missing={},pending={},warnings={},events={}}
  API.compatibility=report
  local phase="Modules"
  Runtime.trace(report,"Execution","START","SEDWARE startup v3; robust LockKey normalization")
  local normalized
  local ok,result=xpcall(function()
   for _,name in moduleNames do getModule(name) end
   Runtime.trace(report,"Modules","READY",tostring(#moduleNames).." embedded modules loaded")
   phase="Configuration"
   if options==nil and headerError then error(headerError,0) end
   local problem
   normalized,problem=getModule("Config").new(if options~=nil then options else initialConfig)
   assert(normalized,problem)
   Runtime.trace(report,"Configuration","READY","PredictionX="..normalized.PredictionX.." PredictionY="..normalized.PredictionY
    .." Enabled="..tostring(normalized.Enabled).." WelcomeNotification="..tostring(normalized.WelcomeNotification)
    .." ShowNotifications="..tostring(normalized.ShowNotifications))
   phase="Services"
   local audit=Runtime.check(normalized)
   audit.events=report.events
   report=Runtime.awaitReady(normalized,audit,function() return request~=generation end)
   if request~=generation or report.cancelled then return nil end
   API.compatibility=report
   if not report.ready then error(Runtime.errorMessage(report),0) end
   for _,warning in report.warnings do Runtime.trace(report,"Compatibility","WARN",warning) end
   phase="Session"
   local session=getModule("Session").init(normalized,report)
   API.session=session
   return session
  end,Runtime.traceback)
  if request~=generation or report.cancelled then
   report.ready=false;report.cancelled=true
   Runtime.trace(report,"Session","CANCELLED","A newer initialization replaced this request")
   return nil,report
  end
  API.compatibility=report
  if ok then return result,report end
  -- Configuration/module errors can occur before the audit. Find PlayerGui
  -- without waiting on an invalid configuration so an error toast can be shown.
  if not report.playerGui then
   local audited,audit=pcall(Runtime.check,normalized)
   if audited then
    report.services=report.services or audit.services
    report.playerGui=audit.playerGui;report.player=audit.player;report.world=audit.world
   end
  end
  phase=report.failurePhase or phase
  report.ready=false;report.error=tostring(result)
  table.insert(report.missing,phase..": "..tostring(result))
  Runtime.trace(report,phase,"FAIL",result)
  local notified,notifyError=pcall(function() getModule("Session").notifyFailure(report,phase..": "..tostring(result)) end)
  if not notified then
   Runtime.reportFailure(phase..": "..tostring(result))
   Runtime.trace(report,"FailureNotification","FAIL",notifyError)
   -- Overlay has no Config/Session dependency; module failures can still show
   -- an error when this small independent public-API display remains usable.
   local shown,fallbackError=pcall(function() return getModule("Overlay").showFailure(report.playerGui,phase..": "..tostring(result)) end)
   if not shown then Runtime.trace(report,"FailureNotification","FAIL",fallbackError) end
  end
  return nil,report
 end
 function API.init(options)
  local session,report=API.tryInit(options)
  if not session then error(Runtime.errorMessage(report),2) end
  return session
 end
 for _,name in {"GetLockedTarget","GetPredictedPosition","GetPrediction","LockTarget","UnlockTarget","IsValidTarget","CreateShotAdapter","SetWeaponProfile","SetPredictionOrigin","SetEnabled","Unload"} do
  API[name]=function(...)
   if not API.session then return nil,"Not initialized" end
   return API.session[name](API.session,...)
  end
 end
 return API
end
return Bootstrap
