--!nonstrict
-- Read-only audit of the native Roblox client APIs used by this laboratory.
-- This describes available capabilities; it does not certify an external host
-- or an experience, and does not use executor APIs, hooks, or protected remotes.
local Runtime = {}

local function member(object, key)
 if object == nil then return nil end
 local ok, value = pcall(function() return object[key] end)
 return if ok then value else nil
end

local function callable(object, key)
 return type(member(object, key)) == "function"
end

local function call(object, key, ...)
 local method = member(object, key)
 if type(method) ~= "function" then return false, nil end
 return pcall(method, object, ...)
end

local function requireMethod(report, object, key, description)
 if callable(object, key) then return true end
 table.insert(report.missing, description or key)
 return false
end

local function requireSignal(report, object, key, description)
 local signal = member(object, key)
 if signal and callable(signal, "Connect") then return true end
 table.insert(report.missing, description or key)
 return false
end

function Runtime.check()
 local report = {
  ready = false, missing = {}, warnings = {}, services = {},
  capabilities = {spherecast = false, networkPing = false, camera = false},
 }
 -- Inspect constructor members without invoking them: the audit creates no
 -- Instances, connections, vectors, casts, JSON payloads, or pending work.
 for _, requirement in {
  {"Instance.new", Instance, "new"}, {"Vector3.new", Vector3, "new"},
  {"Vector2.new", Vector2, "new"}, {"CFrame.lookAt", CFrame, "lookAt"},
  {"UDim.new", UDim, "new"}, {"UDim2.new", UDim2, "new"},
  {"UDim2.fromOffset", UDim2, "fromOffset"}, {"UDim2.fromScale", UDim2, "fromScale"},
  {"Color3.fromRGB", Color3, "fromRGB"}, {"Random.new", Random, "new"},
  {"RaycastParams.new", RaycastParams, "new"},
  {"table.clone", table, "clone"}, {"table.clear", table, "clear"},
  {"math.clamp", math, "clamp"}, {"string.split", string, "split"},
 } do
  requireMethod(report, requirement[2], requirement[3], requirement[1])
 end
 if type(typeof)~="function" then table.insert(report.missing,"typeof de Luau") end
 if Enum == nil or type(Enum) == "boolean" or type(Enum) == "number" or type(Enum) == "string" or type(Enum) == "function" then
  table.insert(report.missing, "Enum de Roblox")
 end

 if not callable(game, "GetService") then
  table.insert(report.missing, "game:GetService (cliente nativo de Roblox)")
 else
  for _, name in {"Players", "RunService", "UserInputService", "GuiService", "HttpService"} do
   local ok, service = call(game, "GetService", name)
   if ok and service then report.services[name] = service
   else table.insert(report.missing, "Servicio " .. name) end
  end
 end

 local services = report.services
 if services.RunService then
  local ok, client = call(services.RunService, "IsClient")
  if not ok or client ~= true then table.insert(report.missing, "RunService:IsClient() debe ser true") end
  requireSignal(report, services.RunService, "RenderStepped", "RunService.RenderStepped.Connect")
 end
 if services.Players then
  requireMethod(report, services.Players, "GetPlayers", "Players:GetPlayers")
  report.player = member(services.Players, "LocalPlayer")
  if report.player == nil then
   table.insert(report.missing, "Players.LocalPlayer")
   table.insert(report.warnings, "LocalPlayer aún no está disponible; vuelve a iniciar cuando termine de cargar el cliente.")
  elseif requireMethod(report, report.player, "FindFirstChild", "LocalPlayer:FindFirstChild") then
   requireMethod(report, report.player, "WaitForChild", "LocalPlayer:WaitForChild")
   local ok, playerGui = call(report.player, "FindFirstChild", "PlayerGui")
   if ok and playerGui ~= nil then
    report.playerGui = playerGui
    requireMethod(report, playerGui, "FindFirstChild", "PlayerGui:FindFirstChild")
   else
    table.insert(report.missing, "LocalPlayer.PlayerGui")
    table.insert(report.warnings, "PlayerGui aún no está disponible; vuelve a iniciar cuando termine de cargar la interfaz.")
   end
  end
 end
 if services.UserInputService then
  local input = services.UserInputService
  requireMethod(report, input, "GetMouseLocation", "UserInputService:GetMouseLocation")
  requireMethod(report, input, "GetFocusedTextBox", "UserInputService:GetFocusedTextBox")
  for _, name in {"InputBegan", "InputEnded", "WindowFocusReleased"} do
   requireSignal(report, input, name, "UserInputService." .. name .. ".Connect")
  end
 end
 if services.GuiService then requireMethod(report, services.GuiService, "GetGuiInset", "GuiService:GetGuiInset") end
 if services.HttpService then
  requireMethod(report, services.HttpService, "JSONEncode", "HttpService:JSONEncode")
  requireMethod(report, services.HttpService, "JSONDecode", "HttpService:JSONDecode")
 end

 report.world = workspace
 if report.world == nil then table.insert(report.missing, "workspace de Roblox")
 else
  requireMethod(report, report.world, "GetServerTimeNow", "Workspace:GetServerTimeNow")
  requireMethod(report, report.world, "Raycast", "Workspace:Raycast")
  requireMethod(report, report.world, "GetPropertyChangedSignal", "Workspace:GetPropertyChangedSignal")
  report.capabilities.spherecast = callable(report.world, "Spherecast")
  report.capabilities.camera = member(report.world, "CurrentCamera") ~= nil
 end
 if not report.capabilities.spherecast then
  table.insert(report.warnings, "Workspace:Spherecast no está disponible; los proyectiles con radio necesitan esta capacidad.")
 end
 report.capabilities.networkPing = callable(report.player, "GetNetworkPing")
 if not report.capabilities.networkPing then
  table.insert(report.warnings, "GetNetworkPing no está disponible; puedes usar RTT simulado o predicción manual.")
 end
 if not report.capabilities.camera then
  table.insert(report.warnings, "CurrentCamera aún no está disponible; la selección esperará a que aparezca.")
 end
 report.ready = #report.missing == 0
 return report
end

function Runtime.errorMessage(report)
 if type(report) ~= "table" then return "No se pudo comprobar el cliente nativo de Roblox." end
 local missing = {}
 for _, value in report.missing or {} do
  if type(value) == "string" then table.insert(missing, value) end
 end
 if #missing == 0 then
  return if report.ready then "Cliente nativo de Roblox disponible." else "El cliente nativo de Roblox no está listo."
 end
 return "No se puede iniciar el laboratorio. Falta: " .. table.concat(missing, "; ") .. "."
end

function Runtime.reportFailure(message)
 local logger=if type(warn)=="function" then warn elseif type(print)=="function" then print else nil
 if logger then
  local text = if type(message) == "string" then message else "No se pudo iniciar el laboratorio local."
  pcall(logger, "[DH PREDICTION LAB] " .. text)
 end
end

return Runtime
