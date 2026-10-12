--!nonstrict
-- Read-only audit and bounded readiness wait: no Instances, event connections,
-- camera writes or remote calls. A ready report only verifies the public client
-- APIs used here; it does not verify a third-party experience or its weapons.
local Runtime = {}

local function text(value)
	local ok, result = pcall(tostring, value)
	return if ok then result else "<error could not be converted to text>"
end
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function member(object, key)
	if object == nil then return nil, nil end
	local ok, result = pcall(function() return object[key] end)
	if ok then return result, nil end
	return nil, text(result)
end
local function callable(object, key)
	return type(member(object, key)) == "function"
end
local function call(object, key, ...)
	local method, problem = member(object, key)
	if type(method) ~= "function" then return false, problem or (key .. " is unavailable") end
	return pcall(method, object, ...)
end
local function missing(report, description, problem)
	table.insert(report.missing, description .. (if problem then ": " .. text(problem) else ""))
end
local function requireMethod(report, object, key, description)
	local method, problem = member(object, key)
	if type(method) == "function" then return true end
	missing(report, description or key, problem)
	return false
end
local function requireSignal(report, object, key, description)
	local signal, problem = member(object, key)
	if problem then missing(report, description or key, problem); return false end
	local connectMethod, connectProblem = member(signal, "Connect")
	if type(connectMethod) == "function" then return true end
	missing(report, description or key, connectProblem)
	return false
end
local function pending(report, description)
	table.insert(report.pending, description)
end

function Runtime.traceback(problem)
	local message = text(problem)
	local traceback = member(debug, "traceback")
	if type(traceback) == "function" then
		local ok, stack = pcall(traceback, message, 2)
		if ok and type(stack) == "string" then return stack end
	end
	return message
end

-- Logging must never make a recoverable initialization error into a new error.
-- It is always enabled; DebugMode controls detailed targeting logs only.
function Runtime.trace(report, phase, status, detail)
	local phaseText, statusText, detailText = text(phase), text(status), text(detail or "")
	pcall(function()
		if type(report) == "table" then
			report.phase = phaseText
			if type(report.events) ~= "table" then report.events = {} end
			if #report.events >= 64 then table.remove(report.events, 1) end
			table.insert(report.events, {phase = phaseText, status = statusText, detail = detailText})
		end
	end)
	local logger = if statusText == "FAIL" and type(warn) == "function" then warn
		elseif type(print) == "function" then print elseif type(warn) == "function" then warn else nil
	local message = "[SEDWARE][" .. phaseText .. "][" .. statusText .. "] " .. detailText
	if logger then
		local logged = pcall(logger, message)
		if not logged and logger ~= print and type(print) == "function" then pcall(print, message) end
	end
	return statusText
end

function Runtime.check(config)
	config = config or {}
	local report = {ready = false, missing = {}, pending = {}, warnings = {}, services = {}, events = {},
		phase = "Services", resources = {},
		capabilities = {networkPing = false, camera = false, visibility = false}}
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
		missing(report, "Enum de Roblox")
	end
	if type(typeof) ~= "function" then missing(report, "typeof de Luau") end
	if config.VisibilityCheck ~= false then
		requireMethod(report, RaycastParams, "new", "RaycastParams.new para VisibilityCheck")
	end

	if requireMethod(report, game, "GetService", "game:GetService del cliente Roblox") then
		for _, name in {"Players", "RunService", "UserInputService", "GuiService", "Workspace"} do
			local ok, service = call(game, "GetService", name)
			if ok and service then report.services[name] = service
			else missing(report, "Servicio " .. name, if ok then "GetService devolvió nil" else service) end
		end
	end
	local services = report.services
	if services.RunService then
		local ok, client = call(services.RunService, "IsClient")
		if not ok then missing(report, "RunService:IsClient()", client)
		elseif client ~= true then missing(report, "RunService:IsClient() debe ser true") end
		requireSignal(report, services.RunService, "RenderStepped", "RunService.RenderStepped.Connect")
	end
	if services.Players then
		requireMethod(report, services.Players, "GetPlayers", "Players:GetPlayers")
		requireSignal(report, services.Players, "PlayerRemoving", "Players.PlayerRemoving.Connect")
		local player, problem = member(services.Players, "LocalPlayer")
		report.player = player
		if problem then
			missing(report, "Players.LocalPlayer", problem)
			report.resources.LocalPlayer = "FAIL"
		elseif not player then
			pending(report, "Players.LocalPlayer")
			report.resources.LocalPlayer = "WAIT"
			report.resources.PlayerGui = "WAIT"
		else
			report.resources.LocalPlayer = "READY"
			if requireMethod(report, player, "FindFirstChild", "LocalPlayer:FindFirstChild") then
				local ok, gui = call(player, "FindFirstChild", "PlayerGui")
				if not ok then
					missing(report, "LocalPlayer:FindFirstChild(\"PlayerGui\")", gui)
					report.resources.PlayerGui = "FAIL"
				elseif not gui then
					pending(report, "LocalPlayer.PlayerGui")
					report.resources.PlayerGui = "WAIT"
				else
					report.playerGui = gui
					report.resources.PlayerGui = if requireMethod(report, gui, "FindFirstChild", "PlayerGui:FindFirstChild") then "READY" else "FAIL"
				end
			else report.resources.PlayerGui = "FAIL" end
		end
	else
		report.resources.LocalPlayer, report.resources.PlayerGui = "FAIL", "FAIL"
	end
	if services.UserInputService then
		local input = services.UserInputService
		requireSignal(report, input, "InputBegan", "UserInputService.InputBegan.Connect")
		requireMethod(report, input, "GetMouseLocation", "UserInputService:GetMouseLocation")
		requireMethod(report, input, "GetFocusedTextBox", "UserInputService:GetFocusedTextBox")
	end
	if services.GuiService then requireMethod(report, services.GuiService, "GetGuiInset", "GuiService:GetGuiInset") end
	report.world = services.Workspace or workspace
	if not report.world then
		missing(report, "Workspace de Roblox")
		report.resources.CurrentCamera = "FAIL"
	else
		requireMethod(report, report.world, "GetServerTimeNow", "Workspace:GetServerTimeNow")
		report.capabilities.visibility = callable(report.world, "Raycast")
		if config.VisibilityCheck ~= false then requireMethod(report, report.world, "Raycast", "Workspace:Raycast para VisibilityCheck") end
		local camera, problem = member(report.world, "CurrentCamera")
		report.camera = camera
		if problem then
			missing(report, "Workspace.CurrentCamera", problem)
			report.resources.CurrentCamera = "FAIL"
		elseif not camera then
			pending(report, "Workspace.CurrentCamera")
			report.resources.CurrentCamera = "WAIT"
		elseif not requireMethod(report, camera, "WorldToViewportPoint", "Camera:WorldToViewportPoint") then
			report.resources.CurrentCamera = "FAIL"
		else
			local size, sizeProblem = member(camera, "ViewportSize")
			local x, xProblem = member(size, "X")
			local y, yProblem = member(size, "Y")
			if sizeProblem or xProblem or yProblem then
				missing(report, "CurrentCamera.ViewportSize", sizeProblem or xProblem or yProblem)
				report.resources.CurrentCamera = "FAIL"
			elseif not finite(x) or not finite(y) or x <= 0 or y <= 0 then
				pending(report, "CurrentCamera.ViewportSize (" .. text(x) .. " x " .. text(y) .. ")")
				report.resources.CurrentCamera = "WAIT"
			else
				report.capabilities.camera = true
				report.resources.CurrentCamera = "READY"
			end
		end
	end
	report.capabilities.networkPing = callable(report.player, "GetNetworkPing")
	if report.player and not report.capabilities.networkPing then
		table.insert(report.warnings, "GetNetworkPing no está disponible; AutoPrediction usa los valores manuales de PredictionX/Y.")
	end
	report.ready = #report.missing == 0 and #report.pending == 0
	return report
end

local function traceResources(report, previous)
	for _, phase in {"LocalPlayer", "PlayerGui", "CurrentCamera"} do
		local status = report.resources[phase] or "FAIL"
		if previous[phase] ~= status then
			previous[phase] = status
			local detail = if status == "READY" then phase .. " preparado."
				elseif status == "WAIT" then phase .. " todavía no está preparado."
				else phase .. " no se pudo validar; consulta el error de Services."
			Runtime.trace(report, phase, status, detail)
		end
	end
end

function Runtime.awaitReady(config, initialReport, cancelled)
	config = config or {}
	local report = initialReport or Runtime.check(config)
	local events, previous = report.events or {}, {}
	report.events = events
	local function stopIfCancelled()
		if type(cancelled) ~= "function" then return false end
		local ok, result = xpcall(cancelled, Runtime.traceback)
		if not ok then
			missing(report, "Comprobación de cancelación de inicialización", result)
			report.ready = false
			return true
		end
		if result then
			report.ready, report.cancelled = false, true
			Runtime.trace(report, "Startup", "CANCELLED", "Una inicialización más reciente reemplazó esta espera.")
			return true
		end
		return false
	end
	if stopIfCancelled() then return report end
	local timeout, interval = config.InitializationTimeout or 8, config.InitializationPollInterval or 0.05
	if not finite(timeout) or timeout < 0.1 or timeout > 30
		or not finite(interval) or interval < 0.01 or interval > 1 then
		missing(report, "InitializationTimeout/InitializationPollInterval fuera de los límites seguros")
		report.ready = false
		return report
	end
	traceResources(report, previous)
	report.phase = "Services"
	if stopIfCancelled() then return report end
	if #report.missing > 0 then return report end
	if report.ready then
		Runtime.trace(report, "Services", "READY", "Servicios y recursos del cliente preparados.")
		return report
	end
	if not callable(task, "wait") then
		missing(report, "task.wait para esperar recursos temporales de Roblox")
		report.ready = false
		return report
	end
	if not callable(os, "clock") then
		missing(report, "os.clock para limitar la espera de inicialización")
		report.ready = false
		return report
	end
	local ok, started = pcall(os.clock)
	if not ok or not finite(started) then
		missing(report, "os.clock durante la inicialización", if ok then "devolvió un valor no finito" else started)
		report.ready = false
		return report
	end
	Runtime.trace(report, "Services", "WAIT", "Esperando hasta " .. text(timeout) .. "s: " .. table.concat(report.pending, "; "))
	local elapsed, iterations, previousClock = 0, 0, started
	local deadlineTolerance = math.min(interval * 1e-6, 1e-6)
	-- A second bound also protects against a broken external task.wait/clock
	-- implementation that returns immediately without advancing monotonic time.
	local maxIterations = math.ceil(timeout / interval) + 1
	while elapsed < timeout - deadlineTolerance and iterations < maxIterations do
		if stopIfCancelled() then return report end
		iterations += 1
		local waited, problem = xpcall(function() task.wait(math.min(interval, timeout - elapsed)) end, Runtime.traceback)
		if stopIfCancelled() then return report end
		if not waited then
			missing(report, "task.wait durante la inicialización", problem)
			report.ready = false
			return report
		end
		local nowOK, now = pcall(os.clock)
		if not nowOK or not finite(now) or now < previousClock then
			missing(report, "os.clock durante la inicialización", if not nowOK then now else "reloj no finito o retrocedió")
			report.ready = false
			return report
		end
		previousClock = now
		elapsed = now - started
		if stopIfCancelled() then return report end
		local nextReport = Runtime.check(config)
		nextReport.events = events
		nextReport.waitedSeconds, nextReport.waitIterations = elapsed, iterations
		report = nextReport
		traceResources(report, previous)
		report.phase = "Services"
		if stopIfCancelled() then return report end
		if #report.missing > 0 then return report end
		if report.ready then
			Runtime.trace(report, "Services", "READY", "Recursos preparados después de " .. text(elapsed) .. "s.")
			return report
		end
	end
	report.ready, report.timedOut = false, true
	report.waitedSeconds, report.waitIterations = elapsed, iterations
	report.phase = "Services"
	report.timeoutSeconds = timeout
	report.waitFailure = if elapsed >= timeout - deadlineTolerance then "Se agotó el tiempo máximo de inicialización (" .. text(timeout) .. "s)."
		else "Se alcanzó el límite seguro de " .. text(maxIterations) .. " consultas; task.wait/os.clock no avanzaron normalmente."
	return report
end

function Runtime.errorMessage(report)
	if type(report) ~= "table" then return "No se pudo comprobar el cliente nativo de Roblox." end
	local reasons = {}
	if type(report.waitFailure) == "string" then table.insert(reasons, report.waitFailure) end
	for _, item in report.missing or {} do table.insert(reasons, text(item)) end
	if #(report.pending or {}) > 0 then table.insert(reasons, "Recursos pendientes: " .. table.concat(report.pending, "; ")) end
	if #reasons == 0 then
		return if report.ready then "Cliente nativo de Roblox disponible." else "El cliente de Roblox no está listo."
	end
	return "SEDWARE no se puede iniciar [" .. text(report.phase or "Services") .. "]. " .. table.concat(reasons, "; ")
end
function Runtime.reportFailure(message)
	local logger = if type(warn) == "function" then warn elseif type(print) == "function" then print else nil
	if logger then
		local description = if type(message) == "string" then message else Runtime.errorMessage(message)
		local output = "[SEDWARE][Load Failed] " .. description
		local logged = pcall(logger, output)
		if not logged and logger ~= print and type(print) == "function" then pcall(print, output) end
	end
end

return Runtime
