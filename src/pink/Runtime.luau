--!nonstrict
-- Read-only audit: no Instances, event connections, camera writes or remote calls.
-- A ready report means the public client APIs used here exist, not that a
-- third-party experience's shot integration has been implemented or verified.
local Runtime = {}

local function member(object, key)
	if object == nil then return nil end
	local ok, result = pcall(function() return object[key] end)
	return if ok then result else nil
end
local function callable(object, key)
	return type(member(object, key)) == "function"
end
local function call(object, key, ...)
	local method = member(object, key)
	if type(method) ~= "function" then return false end
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

function Runtime.check(config)
	config = config or {}
	local report = { ready = false, missing = {}, warnings = {}, services = {},
		capabilities = { networkPing = false, camera = false, visibility = false } }
	for _, requirement in {
		{"Instance.new", Instance, "new"}, {"Vector3.new", Vector3, "new"},
		{"Vector2.new", Vector2, "new"}, {"UDim.new", UDim, "new"},
		{"UDim2.new", UDim2, "new"}, {"UDim2.fromOffset", UDim2, "fromOffset"},
		{"UDim2.fromScale", UDim2, "fromScale"}, {"Color3.fromRGB", Color3, "fromRGB"},
		{"table.clone", table, "clone"}, {"table.clear", table, "clear"},
		{"math.clamp", math, "clamp"},
	} do requireMethod(report, requirement[2], requirement[3], requirement[1]) end
	if Enum == nil or type(Enum) == "boolean" or type(Enum) == "number" or type(Enum) == "string"
		or type(Enum) == "function" then
		table.insert(report.missing, "Enum de Roblox")
	end
	if type(typeof) ~= "function" then table.insert(report.missing, "typeof de Luau") end
	if config.VisibilityCheck ~= false then
		requireMethod(report, RaycastParams, "new", "RaycastParams.new para VisibilityCheck")
	end

	if not callable(game, "GetService") then
		table.insert(report.missing, "game:GetService del cliente Roblox")
	else
		for _, name in {"Players", "RunService", "UserInputService", "GuiService", "Workspace"} do
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
		requireSignal(report, services.Players, "PlayerRemoving", "Players.PlayerRemoving.Connect")
		report.player = member(services.Players, "LocalPlayer")
		if not report.player then table.insert(report.missing, "Players.LocalPlayer")
		else
			if requireMethod(report, report.player, "FindFirstChild", "LocalPlayer:FindFirstChild") then
				local ok, gui = call(report.player, "FindFirstChild", "PlayerGui")
				if ok and gui then report.playerGui = gui
				else table.insert(report.missing, "LocalPlayer.PlayerGui") end
			end
			requireMethod(report, report.player, "WaitForChild", "LocalPlayer:WaitForChild")
		end
		if report.playerGui then
			requireMethod(report, report.playerGui, "FindFirstChild", "PlayerGui:FindFirstChild")
		end
	end
	if services.UserInputService then
		local input = services.UserInputService
		requireSignal(report, input, "InputBegan", "UserInputService.InputBegan.Connect")
		requireMethod(report, input, "GetMouseLocation", "UserInputService:GetMouseLocation")
		requireMethod(report, input, "GetFocusedTextBox", "UserInputService:GetFocusedTextBox")
	end
	if services.GuiService then requireMethod(report, services.GuiService, "GetGuiInset", "GuiService:GetGuiInset") end
	report.world = services.Workspace or workspace
	if not report.world then table.insert(report.missing, "Workspace de Roblox")
	else
		requireMethod(report, report.world, "GetServerTimeNow", "Workspace:GetServerTimeNow")
		report.capabilities.visibility = callable(report.world, "Raycast")
		if config.VisibilityCheck ~= false then requireMethod(report, report.world, "Raycast", "Workspace:Raycast para VisibilityCheck") end
		local camera = member(report.world, "CurrentCamera")
		if not camera then table.insert(report.missing, "Workspace.CurrentCamera")
		else
			report.capabilities.camera = requireMethod(report, camera, "WorldToViewportPoint", "Camera:WorldToViewportPoint")
		end
	end
	report.capabilities.networkPing = callable(report.player, "GetNetworkPing")
	if not report.capabilities.networkPing then
		table.insert(report.warnings, "GetNetworkPing no está disponible; AutoPrediction debe usar los valores manuales de PredictionX/Y.")
	end
	if not report.player or not report.playerGui or not report.capabilities.camera then
		table.insert(report.warnings, "El cliente aún no está listo; vuelve a iniciar después de cargar LocalPlayer, PlayerGui y CurrentCamera.")
	end
	report.ready = #report.missing == 0
	return report
end

function Runtime.errorMessage(report)
	if type(report) ~= "table" then return "No se pudo comprobar el cliente nativo de Roblox." end
	local missing = {}
	for _, item in report.missing or {} do
		if type(item) == "string" then table.insert(missing, item) end
	end
	if #missing == 0 then
		return if report.ready then "Cliente nativo de Roblox disponible." else "El cliente de Roblox no está listo."
	end
	return "PINK DOT LOCK no se puede iniciar. Falta: " .. table.concat(missing, "; ") .. "."
end
function Runtime.reportFailure(message)
	local logger = if type(warn) == "function" then warn elseif type(print) == "function" then print else nil
	if logger then
		local text = if type(message) == "string" then message else Runtime.errorMessage(message)
		pcall(logger, "[PINK DOT LOCK | Load Failed] " .. text)
	end
end

return Runtime
