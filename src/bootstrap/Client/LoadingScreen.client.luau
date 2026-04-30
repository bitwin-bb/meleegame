--!strict

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local PACKAGES_NAME = "Packages"
local REACT_NAME = "React"
local REACT_ROBLOX_NAME = "ReactRoblox"
local BRIDGE_NAME = "AquariaLoaderBridge"
local STATE_CHANGED_NAME = "StateChanged"
local GET_SNAPSHOT_NAME = "GetSnapshot"
local SCREEN_GUI_NAME = "AquariaLoaderGui"
local SPAWN_READY_REMOTE_NAME = "AquariaLoadingScreenReady"
local PACKAGE_WAIT_TIMEOUT_SECONDS = 60
local BRIDGE_WAIT_TIMEOUT_SECONDS = 60
local SPAWN_READY_WAIT_TIMEOUT_SECONDS = 60
local COMPLETE_EXIT_DELAY_SECONDS = 0.25

local function waitForPackageModule(name: string): ModuleScript
	local packages = ReplicatedStorage:WaitForChild(PACKAGES_NAME, PACKAGE_WAIT_TIMEOUT_SECONDS)
	if packages == nil then
		error(`timed out waiting for ReplicatedStorage.{PACKAGES_NAME}`)
	end

	local module = packages:WaitForChild(name, PACKAGE_WAIT_TIMEOUT_SECONDS)
	if module == nil or not module:IsA("ModuleScript") then
		error(`timed out waiting for ReplicatedStorage.{PACKAGES_NAME}.{name}`)
	end

	return module
end

local LoaderGui = require(script.Parent.Parent.UI.Components.LoaderGui)
local React = require(waitForPackageModule(REACT_NAME))
local ReactRoblox = require(waitForPackageModule(REACT_ROBLOX_NAME))
local e: typeof(React.createElement) = React.createElement

type LoaderSnapshot = {
	status: string,
	stage: string,
	message: string,
	progress: number,
	completed: number,
	total: number,
	startedAt: number,
	finishedAt: number?,
	moduleCount: number,
	assetCount: number,
	assetLoadedCount: number,
	assetFailedCount: number,
	failureCount: number,
	lastError: string?,
	failures: { string },
}

type LoadingScreenAppProps = {
	onFinished: (LoaderSnapshot) -> (),
}

local DEFAULT_SNAPSHOT: LoaderSnapshot = {
	status = "idle",
	stage = "boot",
	message = "starting loader",
	progress = 0,
	completed = 0,
	total = 100,
	startedAt = 0,
	finishedAt = nil,
	moduleCount = 0,
	assetCount = 0,
	assetLoadedCount = 0,
	assetFailedCount = 0,
	failureCount = 0,
	lastError = nil,
	failures = {},
}

local function sanitizeNumber(value: any, fallback: number, minimum: number?, maximum: number?): number
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end

	local nextValue = value
	if minimum ~= nil and nextValue < minimum then
		nextValue = minimum
	end
	if maximum ~= nil and nextValue > maximum then
		nextValue = maximum
	end
	return nextValue
end

local function sanitizeString(value: any, fallback: string): string
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function sanitizeStringArray(valueRaw: any): { string }
	local values: { string } = {}
	if typeof(valueRaw) ~= "table" then
		return values
	end

	for _, value in valueRaw do
		if typeof(value) == "string" then
			values[#values + 1] = value
		end
	end

	return values
end

local function sanitizeSnapshot(valueRaw: any): LoaderSnapshot
	local value: { [string]: any } = if typeof(valueRaw) == "table" then valueRaw :: { [string]: any } else {}

	return {
		status = sanitizeString(value.status, DEFAULT_SNAPSHOT.status),
		stage = sanitizeString(value.stage, DEFAULT_SNAPSHOT.stage),
		message = sanitizeString(value.message, DEFAULT_SNAPSHOT.message),
		progress = sanitizeNumber(value.progress, DEFAULT_SNAPSHOT.progress, 0, 1),
		completed = sanitizeNumber(value.completed, DEFAULT_SNAPSHOT.completed, 0, nil),
		total = sanitizeNumber(value.total, DEFAULT_SNAPSHOT.total, 1, nil),
		startedAt = sanitizeNumber(value.startedAt, DEFAULT_SNAPSHOT.startedAt, 0, nil),
		finishedAt = if typeof(value.finishedAt) == "number" then value.finishedAt else nil,
		moduleCount = sanitizeNumber(value.moduleCount, DEFAULT_SNAPSHOT.moduleCount, 0, nil),
		assetCount = sanitizeNumber(value.assetCount, DEFAULT_SNAPSHOT.assetCount, 0, nil),
		assetLoadedCount = sanitizeNumber(value.assetLoadedCount, DEFAULT_SNAPSHOT.assetLoadedCount, 0, nil),
		assetFailedCount = sanitizeNumber(value.assetFailedCount, DEFAULT_SNAPSHOT.assetFailedCount, 0, nil),
		failureCount = sanitizeNumber(value.failureCount, DEFAULT_SNAPSHOT.failureCount, 0, nil),
		lastError = if typeof(value.lastError) == "string" and value.lastError ~= "" then value.lastError else nil,
		failures = sanitizeStringArray(value.failures),
	}
end

local function isTerminalSnapshot(snapshot: LoaderSnapshot): boolean
	return snapshot.status == "complete" or snapshot.status == "failed"
end

local function findBridge(): Folder?
	local bridge = ReplicatedFirst:FindFirstChild(BRIDGE_NAME)
	if bridge ~= nil and bridge:IsA("Folder") then
		return bridge
	end
	return nil
end

local function readAttributeSnapshot(): LoaderSnapshot
	local bridge = findBridge()
	local source = if bridge ~= nil then bridge else ReplicatedFirst

	return sanitizeSnapshot({
		status = source:GetAttribute("AquariaLoaderStatus"),
		stage = source:GetAttribute("AquariaLoaderStage"),
		message = source:GetAttribute("AquariaLoaderMessage"),
		progress = source:GetAttribute("AquariaLoaderProgress"),
		completed = source:GetAttribute("AquariaLoaderCompleted"),
		total = source:GetAttribute("AquariaLoaderTotal"),
		startedAt = source:GetAttribute("AquariaLoaderStartedAt"),
		finishedAt = source:GetAttribute("AquariaLoaderFinishedAt"),
		moduleCount = source:GetAttribute("AquariaLoaderModuleCount"),
		assetCount = source:GetAttribute("AquariaLoaderAssetCount"),
		assetLoadedCount = source:GetAttribute("AquariaLoaderAssetLoadedCount"),
		assetFailedCount = source:GetAttribute("AquariaLoaderAssetFailedCount"),
		failureCount = source:GetAttribute("AquariaLoaderFailureCount"),
		lastError = source:GetAttribute("AquariaLoaderLastError"),
	})
end

local function readBridgeSnapshot(): LoaderSnapshot
	local bridge = findBridge()
	if bridge == nil then
		return readAttributeSnapshot()
	end

	local getSnapshot = bridge:FindFirstChild(GET_SNAPSHOT_NAME)
	if getSnapshot == nil or not getSnapshot:IsA("BindableFunction") then
		return readAttributeSnapshot()
	end

	local ok, result = pcall(function()
		return getSnapshot:Invoke()
	end)
	if ok then
		return sanitizeSnapshot(result)
	end

	return readAttributeSnapshot()
end

local function subscribeToSnapshots(onSnapshot: (LoaderSnapshot) -> ()): () -> ()
	local cancelled = false
	local connection = nil :: RBXScriptConnection?

	task.spawn(function()
		local bridge = findBridge()
		if bridge == nil then
			local foundBridge = ReplicatedFirst:WaitForChild(BRIDGE_NAME, BRIDGE_WAIT_TIMEOUT_SECONDS)
			bridge = if foundBridge ~= nil and foundBridge:IsA("Folder") then foundBridge else nil
		end
		if cancelled or bridge == nil then
			return
		end

		local changed = bridge:FindFirstChild(STATE_CHANGED_NAME)
		if changed == nil then
			changed = bridge:WaitForChild(STATE_CHANGED_NAME, BRIDGE_WAIT_TIMEOUT_SECONDS)
		end
		if cancelled or changed == nil or not changed:IsA("BindableEvent") then
			return
		end

		onSnapshot(readBridgeSnapshot())
		connection = changed.Event:Connect(function(snapshotRaw: any)
			onSnapshot(sanitizeSnapshot(snapshotRaw))
		end)
	end)

	return function()
		cancelled = true
		if connection ~= nil then
			connection:Disconnect()
			connection = nil
		end
	end
end

local function getLocalPlayer(): Player
	local player = Players.LocalPlayer
	while player == nil do
		Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
		player = Players.LocalPlayer
	end
	return player
end

local function ensureScreenGui(): ScreenGui
	local player = getLocalPlayer()
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local existing = playerGui:FindFirstChild(SCREEN_GUI_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = SCREEN_GUI_NAME
	screenGui.DisplayOrder = 100000
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui
	return screenGui
end

local function fireSpawnReady(snapshot: LoaderSnapshot): boolean
	local deadline = os.clock() + SPAWN_READY_WAIT_TIMEOUT_SECONDS
	while os.clock() < deadline do
		local remote = ReplicatedStorage:FindFirstChild(SPAWN_READY_REMOTE_NAME)
		if remote ~= nil and remote:IsA("RemoteEvent") then
			remote:FireServer(snapshot.status)
			return true
		end
		task.wait(0.2)
	end

	warn("[AquariaLoadingScreen] timed out waiting for spawn ready remote")
	return false
end

local function LoadingScreenApp(props: LoadingScreenAppProps): React.ReactNode
	local snapshot, setSnapshot = React.useState(function(): LoaderSnapshot
		return readBridgeSnapshot()
	end)
	local finishedRef = React.useRef(false)

	React.useEffect(function()
		return subscribeToSnapshots(setSnapshot)
	end, {})

	React.useEffect(function()
		if finishedRef.current or not isTerminalSnapshot(snapshot) then
			return
		end

		finishedRef.current = true
		props.onFinished(snapshot)
	end, { snapshot.status })

	return e(LoaderGui, {
		snapshot = snapshot,
	})
end

local screenGui = ensureScreenGui()
local root = ReactRoblox.createRoot(screenGui)
local destroyed = false
local spawnReadyStarted = false

local function destroy()
	if destroyed then
		return
	end

	destroyed = true
	root:unmount()
	if screenGui.Parent ~= nil then
		screenGui:Destroy()
	end
end

local function onFinished(snapshot: LoaderSnapshot)
	if spawnReadyStarted then
		return
	end
	spawnReadyStarted = true

	task.spawn(function()
		fireSpawnReady(snapshot)
		task.delay(COMPLETE_EXIT_DELAY_SECONDS, destroy)
	end)
end

local player = getLocalPlayer()
local playerConnection = player.AncestryChanged:Connect(function()
	if not player:IsDescendantOf(game) then
		destroy()
	end
end)

root:render(e(LoadingScreenApp, {
	onFinished = onFinished,
}))

screenGui.Destroying:Connect(function()
	playerConnection:Disconnect()
end)
