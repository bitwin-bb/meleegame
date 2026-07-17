local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local PacketPayload = require("PacketPayload")
local PlayerDataServicePackets = require("NetPacketsShared").PlayerDataService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = PlayerDataServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for PlayerDataService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = PlayerDataServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for PlayerDataService`)
		return
	end

	packet.listen(function(payload: any, player: Player?)
		if player == nil then
			return
		end

		local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, player, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "requestSync")
end

local Configs = require("CoreConfigs")
local DataTemplate = require("DataTemplate")
local PlayerDataServiceUtils = require("PlayerDataServiceUtils")
local Promise: any = require("Promise")

local function fulfilledPromise(...): any
	local args = table.pack(...)
	return Promise.new(function(fulfill)
		fulfill(table.unpack(args, 1, args.n))
	end)
end
local Signal = require("Signal")

local SERVER_PACKAGE_LOAD_TIMEOUT_SECONDS = 10

local function getServerPackage(packageName: string): ModuleScript
	local serverPackages = game:GetService("ServerScriptService"):FindFirstChild("ServerPackages")
		or game:GetService("ServerScriptService"):WaitForChild("ServerPackages", SERVER_PACKAGE_LOAD_TIMEOUT_SECONDS)
	assert(serverPackages ~= nil, `[PlayerDataServiceServer] Missing ServerScriptService.ServerPackages.`)

	local package = serverPackages:FindFirstChild(packageName)
		or serverPackages:WaitForChild(packageName, SERVER_PACKAGE_LOAD_TIMEOUT_SECONDS)
	assert(
		package ~= nil and package:IsA("ModuleScript"),
		`[PlayerDataServiceServer] Missing ServerPackages.{packageName}.`
	)

	return package
end

local ProfileStore = require(getServerPackage("ProfileStore") :: any)

type PlayerData = PlayerDataServiceUtils.PlayerData
type LoadState = string
type Profile = any
type ProfileStoreObject = any
type ProfileSignalConnection = {
	Disconnect: (self: ProfileSignalConnection) -> (),
}

type StateChangedSignal = Signal.Signal<...any>

type PlayerRuntime = {
	loadToken: number,
	loadState: LoadState,
	profile: Profile?,
	data: PlayerData?,
	isLoading: boolean,
	hasInitialLoad: boolean,
	lastFailureReason: string?,
	loadStartedAt: number,
	usingFallbackData: boolean,
	fallbackBaselineData: PlayerData?,
	fallbackDirty: boolean,
	profileEndedConnection: ProfileSignalConnection?,
	stateChangedSignal: StateChangedSignal,
	loadPromise: any?,
}

local PlayerDataServiceServer = {}
PlayerDataServiceServer.ServiceName = "PlayerDataServiceServer"

local DATA_SESSION_ENDED_KICK_MESSAGE = "Your data session ended. Please rejoin."
local PROFILE_FALLBACK_DATASTORE_TIMEOUT_SECONDS = 2
local PROFILE_SESSION_START_TIMEOUT_SECONDS = 5

local function promiseTry<T...>(callback: () -> T...): any
	return Promise.spawn(function(fulfill, reject)
		local results = table.pack(pcall(callback))
		if results[1] then
			fulfill(table.unpack(results, 2, results.n))
		else
			reject(table.unpack(results, 2, results.n))
		end
	end)
end

local function getPlayerDataTemplate(): PlayerData
	local templateRoot = if typeof(DataTemplate) == "table" then DataTemplate else {} :: any
	local playerData = if typeof((templateRoot :: any).playerData) == "table"
		then (templateRoot :: any).playerData
		else {} :: any
	return PlayerDataServiceUtils.CreateDefaultData(playerData)
end

local function runProtectedWithTimeout(timeoutSeconds: number, callback: () -> any): (string, boolean, any)
	local bindable = Instance.new("BindableEvent")
	local settled = false

	local function settle(status: string, success: boolean, result: any)
		if settled then
			return
		end
		settled = true
		bindable:Fire(status, success, result)
	end

	task.spawn(function()
		local success, result = pcall(callback)
		settle("completed", success, result)
	end)

	task.delay(math.max(0, timeoutSeconds), function()
		settle("timed_out", false, nil)
	end)

	local status, success, result = bindable.Event:Wait()
	bindable:Destroy()
	return status, success, result
end

local function coerceFailureReason(reasonRaw: any): string?
	if typeof(reasonRaw) ~= "string" then
		return nil
	end
	local trimmedReason = string.match(reasonRaw, "^%s*(.-)%s*$") or ""
	if trimmedReason == "" then
		return nil
	end
	return trimmedReason
end

local function stringifyLogValue(valueRaw: any): string
	if valueRaw == nil then
		return "nil"
	end
	local valueType = typeof(valueRaw)
	if valueType == "string" or valueType == "number" or valueType == "boolean" then
		return tostring(valueRaw)
	end
	return valueType
end

function PlayerDataServiceServer.Init(self: PlayerDataServiceServer, _serviceBag: any?)
	self.dataTemplate = getPlayerDataTemplate()
	self.profileStore = ProfileStore.New(PlayerDataServiceUtils.DEFAULT_PROFILE_STORE_NAME, self.dataTemplate)
	self.playerRuntimes = {}
	bindPackets(self)

	for _, player in Players:GetPlayers() do
		self:TrackPlayer(player)
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self:TrackPlayer(player)
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:UntrackPlayer(player)
	end)
end

function PlayerDataServiceServer.CreateRuntime(_self: PlayerDataServiceServer): PlayerRuntime
	return {
		loadToken = 0,
		loadState = PlayerDataServiceUtils.LOAD_STATE_UNLOADED,
		profile = nil,
		data = nil,
		isLoading = false,
		hasInitialLoad = false,
		lastFailureReason = nil,
		loadStartedAt = 0,
		usingFallbackData = false,
		fallbackBaselineData = nil,
		fallbackDirty = false,
		profileEndedConnection = nil,
		stateChangedSignal = Signal.new() :: StateChangedSignal,
		loadPromise = nil,
	}
end

function PlayerDataServiceServer.GetRuntime(self: PlayerDataServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime then
		return runtime
	end

	local nextRuntime = self:CreateRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function PlayerDataServiceServer.GetRuntimeLoadElapsedSeconds(
	_self: PlayerDataServiceServer,
	runtime: PlayerRuntime
): number
	if runtime.loadStartedAt <= 0 then
		return 0
	end
	return math.max(0, os.clock() - runtime.loadStartedAt)
end

function PlayerDataServiceServer.IsMockDataEnabled(_self: PlayerDataServiceServer): boolean
	return typeof(Configs) == "table" and (Configs :: any).addMock == true
end

function PlayerDataServiceServer.GetRuntimeStateMetadata(
	self: PlayerDataServiceServer,
	runtime: PlayerRuntime
): { [string]: any }
	return {
		isLoading = runtime.isLoading,
		hasInitialLoad = runtime.hasInitialLoad,
		loadToken = runtime.loadToken,
		lastFailureReason = runtime.lastFailureReason,
		loadElapsedSeconds = self:GetRuntimeLoadElapsedSeconds(runtime),
	}
end

function PlayerDataServiceServer.LogEvent(
	self: PlayerDataServiceServer,
	eventName: string,
	player: Player,
	runtime: PlayerRuntime?,
	extraFieldsRaw: any
)
	local fields = {
		("event=%s"):format(eventName),
		("player=%s"):format(player.Name),
		("userId=%d"):format(player.UserId),
	}
	if runtime ~= nil then
		fields[#fields + 1] = ("loadState=%s"):format(runtime.loadState)
		fields[#fields + 1] = ("isLoading=%s"):format(tostring(runtime.isLoading))
		fields[#fields + 1] = ("hasInitialLoad=%s"):format(tostring(runtime.hasInitialLoad))
		fields[#fields + 1] = ("loadToken=%d"):format(runtime.loadToken)
		fields[#fields + 1] = ("elapsed=%.3f"):format(self:GetRuntimeLoadElapsedSeconds(runtime))
		if runtime.lastFailureReason ~= nil then
			fields[#fields + 1] = ("lastFailureReason=%s"):format(runtime.lastFailureReason)
		end
	end
	if typeof(extraFieldsRaw) == "table" then
		for key, value in extraFieldsRaw :: { [string]: any } do
			fields[#fields + 1] = ("%s=%s"):format(tostring(key), stringifyLogValue(value))
		end
	end
end

function PlayerDataServiceServer.DisconnectProfileEndedConnection(
	_self: PlayerDataServiceServer,
	runtime: PlayerRuntime
)
	local connection = runtime.profileEndedConnection
	if connection == nil then
		return
	end

	connection:Disconnect()
	runtime.profileEndedConnection = nil
end

function PlayerDataServiceServer.ReleaseProfile(self: PlayerDataServiceServer, runtime: PlayerRuntime)
	self:DisconnectProfileEndedConnection(runtime)

	local profile = runtime.profile
	runtime.profile = nil
	runtime.data = nil
	runtime.usingFallbackData = false
	runtime.fallbackBaselineData = nil
	runtime.fallbackDirty = false

	if profile and profile:IsActive() then
		profile:EndSession()
	end
end

function PlayerDataServiceServer.EmitRuntimeStateChanged(_self: PlayerDataServiceServer, runtime: PlayerRuntime)
	runtime.stateChangedSignal:Fire()
end

function PlayerDataServiceServer.PushState(self: PlayerDataServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]

	if runtime == nil then
		sendPacket(player, "applyState", nil, PlayerDataServiceUtils.LOAD_STATE_UNLOADED, {
			isLoading = false,
			hasInitialLoad = false,
			loadToken = 0,
			lastFailureReason = nil,
			loadElapsedSeconds = 0,
		})
		return
	end

	local dataSnapshot = if runtime.data ~= nil then PlayerDataServiceUtils.CloneDeep(runtime.data) else nil
	sendPacket(player, "applyState", dataSnapshot, runtime.loadState, self:GetRuntimeStateMetadata(runtime))
	self:EmitRuntimeStateChanged(runtime)
end

function PlayerDataServiceServer.GetLoadedRuntime(self: PlayerDataServiceServer, player: Player): PlayerRuntime?
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return nil
	end
	if runtime.loadState ~= PlayerDataServiceUtils.LOAD_STATE_LOADED then
		return nil
	end
	if runtime.data == nil then
		return nil
	end
	return runtime
end

function PlayerDataServiceServer.GetAvailableRuntime(self: PlayerDataServiceServer, player: Player): PlayerRuntime?
	local runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.data == nil then
		return nil
	end
	if runtime.loadState == PlayerDataServiceUtils.LOAD_STATE_LOADED then
		return runtime
	end
	if runtime.hasInitialLoad then
		return runtime
	end
	return nil
end

function PlayerDataServiceServer.GetPersistedDataSnapshot(
	self: PlayerDataServiceServer,
	rawSnapshotRaw: any
): PlayerData
	local rawSnapshot = rawSnapshotRaw
	if typeof(rawSnapshot) == "table" and typeof((rawSnapshot :: { [string]: any }).Data) == "table" then
		rawSnapshot = (rawSnapshot :: { [string]: any }).Data
	end

	local Got = if typeof(rawSnapshot) == "table"
		then PlayerDataServiceUtils.CloneDeep(rawSnapshot)
		else PlayerDataServiceUtils.CreateDefaultData(self.dataTemplate)
	PlayerDataServiceUtils.ReconcileData(Got, self.dataTemplate)
	return Got
end

function PlayerDataServiceServer.GetFallbackLoadResult(
	self: PlayerDataServiceServer,
	player: Player
): (boolean, PlayerData?, string, string)
	local profileKey = PlayerDataServiceUtils.GetProfileKey(player)
	if profileKey == nil then
		return false, nil, "default", "profile_key_invalid"
	end

	local profileStore = self.profileStore
	local rawDataStore = if typeof(profileStore) == "table" then (profileStore :: any).data_store else nil
	if rawDataStore == nil then
		return false, nil, "default", "datastore_unavailable"
	end

	local completionStatus, didLoad, rawSnapshot = runProtectedWithTimeout(
		PROFILE_FALLBACK_DATASTORE_TIMEOUT_SECONDS,
		function()
			return rawDataStore:GetAsync(profileKey)
		end
	)
	if completionStatus == "timed_out" then
		return false, nil, "default", "fallback_timeout"
	end
	if not didLoad then
		return false, nil, "default", "fallback_error:" .. tostring(rawSnapshot)
	end

	return true,
		self:GetPersistedDataSnapshot(rawSnapshot),
		if rawSnapshot == nil then "default" else "datastore",
		if rawSnapshot == nil then "fallback_default_data" else "fallback_datastore"
end

function PlayerDataServiceServer.StartProfileLoad(self: PlayerDataServiceServer, player: Player, runtime: PlayerRuntime)
	local currentLoadToken = runtime.loadToken
	if runtime.loadPromise ~= nil then
		return
	end

	runtime.loadPromise = self:LoadProfilePromise(player, currentLoadToken):Finally(function()
		local currentRuntime = self.playerRuntimes[player]
		if currentRuntime ~= nil and currentRuntime.loadToken == currentLoadToken then
			currentRuntime.loadPromise = nil
		end
	end)
end

function PlayerDataServiceServer.FinalizeLoadedRuntime(
	self: PlayerDataServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	loadToken: number,
	dataRaw: any,
	sourceRaw: any,
	reasonRaw: any,
	profileRaw: Profile?
): boolean
	local currentRuntime = self.playerRuntimes[player]
	if currentRuntime == nil or currentRuntime ~= runtime or runtime.loadToken ~= loadToken then
		local profile = profileRaw
		if profile ~= nil and profile:IsActive() then
			profile:EndSession()
		end
		return false
	end

	local playerData = self:GetPersistedDataSnapshot(dataRaw)
	self:DisconnectProfileEndedConnection(runtime)
	runtime.profile = profileRaw
	runtime.data = playerData
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_LOADED
	runtime.isLoading = false
	runtime.hasInitialLoad = true
	runtime.lastFailureReason = nil
	runtime.usingFallbackData = runtime.profile == nil
	runtime.fallbackBaselineData = if runtime.usingFallbackData
		then PlayerDataServiceUtils.CloneDeep(playerData)
		else nil
	runtime.fallbackDirty = false
	if runtime.profile ~= nil then
		local activeProfile = runtime.profile :: Profile
		runtime.profileEndedConnection = activeProfile.OnSessionEnd:Connect(function()
			self:OnProfileSessionEnded(player, activeProfile)
		end)
	end
	self:PushState(player)
	self:LogEvent("load_success", player, runtime, {
		source = sourceRaw,
		reason = reasonRaw,
	})
	return true
end

function PlayerDataServiceServer.FinalizeFailedRuntime(
	self: PlayerDataServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	loadToken: number,
	reasonRaw: any
): boolean
	local currentRuntime = self.playerRuntimes[player]
	if currentRuntime == nil or currentRuntime ~= runtime or runtime.loadToken ~= loadToken then
		return false
	end

	self:DisconnectProfileEndedConnection(runtime)
	runtime.profile = nil
	runtime.data = PlayerDataServiceUtils.CreateDefaultData(self.dataTemplate)
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_FAILED
	runtime.isLoading = false
	runtime.hasInitialLoad = true
	runtime.lastFailureReason = coerceFailureReason(reasonRaw) or "unknown"
	runtime.usingFallbackData = false
	runtime.fallbackBaselineData = nil
	runtime.fallbackDirty = false
	self:PushState(player)
	self:LogEvent("load_failed_terminal", player, runtime, {
		reason = runtime.lastFailureReason,
	})
	return true
end

function PlayerDataServiceServer.OnProfileSessionEnded(self: PlayerDataServiceServer, player: Player, profile: Profile)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end
	if runtime.profile ~= profile then
		return
	end

	self:DisconnectProfileEndedConnection(runtime)
	runtime.profile = nil
	runtime.data = PlayerDataServiceUtils.CreateDefaultData(self.dataTemplate)
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_FAILED
	runtime.isLoading = false
	runtime.hasInitialLoad = true
	runtime.lastFailureReason = "session_ended"
	runtime.usingFallbackData = false
	runtime.fallbackBaselineData = nil
	runtime.fallbackDirty = false
	self:PushState(player)

	if player.Parent == Players and not ProfileStore.IsClosing then
		player:Kick(DATA_SESSION_ENDED_KICK_MESSAGE)
	end
end

function PlayerDataServiceServer.LoadProfilePromise(self: PlayerDataServiceServer, player: Player, loadToken: number)
	return promiseTry(function()
		local runtime = self.playerRuntimes[player]
		if runtime == nil or runtime.loadToken ~= loadToken then
			return nil
		end
		self:LogEvent("load_begin", player, runtime, nil)

		if self:IsMockDataEnabled() then
			local mockData = PlayerDataServiceUtils.CreateDefaultData(self.dataTemplate)
			self:FinalizeLoadedRuntime(player, runtime, loadToken, mockData, "mock", "mock_enabled", nil)
			return mockData :: any
		end

		local profileKey = PlayerDataServiceUtils.GetProfileKey(player)
		if profileKey == nil then
			self:FinalizeFailedRuntime(player, runtime, loadToken, "profile_key_invalid")
			return nil
		end

		local loadDeadline = os.clock() + PROFILE_SESSION_START_TIMEOUT_SECONDS
		local profile: Profile? = nil
		local success, resultOrError = (pcall :: any)(function()
			return self.profileStore:StartSessionAsync(profileKey, {
				Cancel = function()
					local currentRuntime = self.playerRuntimes[player]
					if currentRuntime == nil then
						return true
					end
					if currentRuntime.loadToken ~= loadToken then
						return true
					end
					if player.Parent ~= Players then
						return true
					end
					return os.clock() >= loadDeadline
				end,
			})
		end)
		if success then
			profile = resultOrError :: Profile?
		end

		runtime = self.playerRuntimes[player]
		if runtime == nil or runtime.loadToken ~= loadToken then
			if profile and profile:IsActive() then
				profile:EndSession()
			end
			return nil
		end

		if profile == nil then
			local primaryFailureReason = if success
				then if os.clock() >= loadDeadline then "profile_timeout" else "profile_session_unavailable"
				else "profile_error:" .. tostring(resultOrError)
			local fallbackSuccess, fallbackData, fallbackSource, fallbackReason = self:GetFallbackLoadResult(player)
			runtime = self.playerRuntimes[player]
			if runtime == nil or runtime.loadToken ~= loadToken then
				return nil
			end
			if fallbackSuccess and fallbackData ~= nil then
				self:FinalizeLoadedRuntime(
					player,
					runtime,
					loadToken,
					fallbackData,
					fallbackSource,
					primaryFailureReason .. "|" .. fallbackReason,
					nil
				)
				return fallbackData :: any
			end
			self:FinalizeFailedRuntime(player, runtime, loadToken, primaryFailureReason .. "|" .. fallbackReason)
			return nil
		end

		profile:AddUserId(player.UserId)
		profile:Reconcile()

		local profileData = profile.Data
		if typeof(profileData) ~= "table" then
			profileData = PlayerDataServiceUtils.CreateDefaultData(self.dataTemplate)
			profile.Data = profileData
		end
		PlayerDataServiceUtils.ReconcileData(profileData, self.dataTemplate)
		self:FinalizeLoadedRuntime(player, runtime, loadToken, profileData, "profile", "profile_loaded", profile)
		return profileData
	end):Catch(function(err: any)
		local runtime = self.playerRuntimes[player]
		if runtime ~= nil and runtime.loadToken == loadToken then
			self:FinalizeFailedRuntime(player, runtime, loadToken, "unexpected_error:" .. tostring(err))
		end
		return nil
	end)
end

function PlayerDataServiceServer.TrackPlayer(self: PlayerDataServiceServer, player: Player)
	local runtime = self:GetRuntime(player)
	if runtime.isLoading or runtime.hasInitialLoad then
		self:PushState(player)
		return
	end
	runtime.loadToken += 1
	self:ReleaseProfile(runtime)
	runtime.data = nil
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_LOADING
	runtime.isLoading = true
	runtime.hasInitialLoad = false
	runtime.lastFailureReason = nil
	runtime.loadStartedAt = os.clock()
	runtime.usingFallbackData = false
	runtime.fallbackBaselineData = nil
	runtime.fallbackDirty = false
	self:LogEvent("trackPlayer_start", player, runtime, nil)
	self:PushState(player)
	self:StartProfileLoad(player, runtime)
end

function PlayerDataServiceServer.UntrackPlayer(self: PlayerDataServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	runtime.loadToken += 1
	if runtime.loadPromise ~= nil then
		runtime.loadPromise:Destroy()
		runtime.loadPromise = nil
	end
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_UNLOADED
	runtime.isLoading = false
	runtime.hasInitialLoad = false
	runtime.lastFailureReason = nil
	runtime.loadStartedAt = 0
	self:EmitRuntimeStateChanged(runtime)
	self.playerRuntimes[player] = nil
	self:ReleaseProfile(runtime)
	runtime.stateChangedSignal:Destroy()
end

function PlayerDataServiceServer.GetActiveRuntime(self: PlayerDataServiceServer, player: Player): PlayerRuntime?
	local runtime = self:GetLoadedRuntime(player)
	if runtime == nil then
		return nil
	end
	local profile = runtime.profile
	if profile == nil or not profile:IsActive() then
		return nil
	end

	return runtime
end

function PlayerDataServiceServer.RequestSync(self: PlayerDataServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		self:TrackPlayer(player)
		return
	end

	self:PushState(player)
end

function PlayerDataServiceServer.GetLoadState(self: PlayerDataServiceServer, player: Player): LoadState
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return PlayerDataServiceUtils.LOAD_STATE_UNLOADED
	end
	return runtime.loadState
end

function PlayerDataServiceServer.IsLoaded(self: PlayerDataServiceServer, player: Player): boolean
	return self:GetLoadedRuntime(player) ~= nil
end

function PlayerDataServiceServer.WaitForData(
	self: PlayerDataServiceServer,
	player: Player,
	timeoutSecondsRaw: any
): PlayerData?
	local success, result = self:WaitForDataPromise(player, timeoutSecondsRaw):Yield()
	if not success then
		return nil
	end
	return result :: PlayerData?
end

function PlayerDataServiceServer.WaitForDataPromise(
	self: PlayerDataServiceServer,
	player: Player,
	timeoutSecondsRaw: any
)
	local timeoutSeconds = if typeof(timeoutSecondsRaw) == "number" and timeoutSecondsRaw == timeoutSecondsRaw
		then math.max(0, timeoutSecondsRaw)
		else 15

	local function getIfReady(): PlayerData?
		local availableRuntime = self:GetAvailableRuntime(player)
		if availableRuntime ~= nil and availableRuntime.data ~= nil then
			return availableRuntime.data
		end
		return nil
	end

	local immediateData = getIfReady()
	if immediateData ~= nil then
		return fulfilledPromise(immediateData)
	end

	local trackedRuntime = self.playerRuntimes[player]
	if trackedRuntime == nil then
		return fulfilledPromise(nil)
	end
	if trackedRuntime.hasInitialLoad then
		return fulfilledPromise(getIfReady())
	end

	if timeoutSeconds <= 0 then
		return fulfilledPromise(nil)
	end

	return Promise.new(function(fulfill, _reject)
		local connection = nil :: any?
		local settled = false

		local function cleanup()
			if connection ~= nil then
				connection:Disconnect()
				connection = nil
			end
		end

		local function settle(result: PlayerData?)
			if settled then
				return
			end
			settled = true
			cleanup()
			fulfill(result)
		end

		connection = trackedRuntime.stateChangedSignal:Connect(function()
			local currentRuntime = self.playerRuntimes[player]
			if currentRuntime == nil or currentRuntime.hasInitialLoad or getIfReady() ~= nil then
				settle(getIfReady())
			end
		end)

		local readyData = getIfReady()
		if readyData ~= nil or trackedRuntime.hasInitialLoad then
			settle(readyData)
			return
		end

		task.delay(timeoutSeconds, function()
			settle(nil)
		end)
	end)
end

function PlayerDataServiceServer.GetProfile(self: PlayerDataServiceServer, player: Player): Profile?
	local runtime = self:GetActiveRuntime(player)
	if runtime == nil then
		return nil
	end
	return runtime.profile
end

function PlayerDataServiceServer.GetData(self: PlayerDataServiceServer, player: Player): PlayerData?
	local runtime = self:GetAvailableRuntime(player)
	if runtime == nil then
		return nil
	end
	return runtime.data
end

function PlayerDataServiceServer.GetDataCopy(self: PlayerDataServiceServer, player: Player): PlayerData?
	local data = self:GetData(player)
	if data == nil then
		return nil
	end
	return PlayerDataServiceUtils.CloneDeep(data)
end

function PlayerDataServiceServer.GetValue(
	self: PlayerDataServiceServer,
	player: Player,
	pathRaw: any,
	fallback: any
): any
	local data = self:GetData(player)
	if data == nil then
		return fallback
	end
	return PlayerDataServiceUtils.GetValueAtPath(data, pathRaw, fallback)
end

function PlayerDataServiceServer.GetHpData(self: PlayerDataServiceServer, player: Player, fallback: any): any
	return self:GetValue(player, PlayerDataServiceUtils.GetDefaultHpDataPath(), fallback)
end

function PlayerDataServiceServer.GetCoinsData(self: PlayerDataServiceServer, player: Player, fallback: any): any
	return self:GetValue(player, PlayerDataServiceUtils.GetDefaultCoinsDataPath(), fallback)
end

function PlayerDataServiceServer.SetValue(
	self: PlayerDataServiceServer,
	player: Player,
	pathRaw: any,
	value: any,
	replicateToClientRaw: any
): boolean
	local runtime = self:GetLoadedRuntime(player)
	if runtime == nil or runtime.data == nil then
		return false
	end

	local didSet = PlayerDataServiceUtils.SetValueAtPath(runtime.data, pathRaw, value)
	if didSet and runtime.usingFallbackData then
		runtime.fallbackDirty = true
	end
	if didSet and replicateToClientRaw ~= false then
		self:PushState(player)
	end
	return didSet
end

function PlayerDataServiceServer.SetHpData(
	self: PlayerDataServiceServer,
	player: Player,
	hpDataRaw: any,
	replicateToClientRaw: any
): boolean
	return self:SetValue(player, PlayerDataServiceUtils.GetDefaultHpDataPath(), hpDataRaw, replicateToClientRaw)
end

function PlayerDataServiceServer.SetCoinsData(
	self: PlayerDataServiceServer,
	player: Player,
	coinsDataRaw: any,
	replicateToClientRaw: any
): boolean
	return self:SetValue(player, PlayerDataServiceUtils.GetDefaultCoinsDataPath(), coinsDataRaw, replicateToClientRaw)
end

function PlayerDataServiceServer.RemoveValue(
	self: PlayerDataServiceServer,
	player: Player,
	pathRaw: any,
	replicateToClientRaw: any
): boolean
	local runtime = self:GetLoadedRuntime(player)
	if runtime == nil or runtime.data == nil then
		return false
	end

	local didRemove = PlayerDataServiceUtils.RemoveValueAtPath(runtime.data, pathRaw)
	if didRemove and runtime.usingFallbackData then
		runtime.fallbackDirty = true
	end
	if didRemove and replicateToClientRaw ~= false then
		self:PushState(player)
	end
	return didRemove
end

function PlayerDataServiceServer.IncrementValue(
	self: PlayerDataServiceServer,
	player: Player,
	pathRaw: any,
	amountRaw: any,
	fallbackValueRaw: any,
	replicateToClientRaw: any
): number?
	local runtime = self:GetLoadedRuntime(player)
	if runtime == nil or runtime.data == nil then
		return nil
	end

	local nextValue = PlayerDataServiceUtils.IncrementValueAtPath(runtime.data, pathRaw, amountRaw, fallbackValueRaw)
	if nextValue ~= nil and runtime.usingFallbackData then
		runtime.fallbackDirty = true
	end
	if nextValue ~= nil and replicateToClientRaw ~= false then
		self:PushState(player)
	end
	return nextValue
end

function PlayerDataServiceServer.MergeData(
	self: PlayerDataServiceServer,
	player: Player,
	incomingDataRaw: any,
	replicateToClientRaw: any
): boolean
	local runtime = self:GetLoadedRuntime(player)
	if runtime == nil or runtime.data == nil then
		return false
	end

	local didMerge = PlayerDataServiceUtils.MergeData(runtime.data, incomingDataRaw)
	if didMerge and runtime.usingFallbackData then
		runtime.fallbackDirty = true
	end
	if didMerge and replicateToClientRaw ~= false then
		self:PushState(player)
	end
	return didMerge
end

function PlayerDataServiceServer.SavePlayerData(self: PlayerDataServiceServer, player: Player): boolean
	local success, result = self:SavePlayerDataPromise(player):Yield()
	if not success then
		return false
	end
	return result == true
end

function PlayerDataServiceServer.SavePlayerDataPromise(self: PlayerDataServiceServer, player: Player)
	return promiseTry(function()
		local runtime = self:GetActiveRuntime(player)
		if runtime == nil then
			return false
		end

		local profile = runtime.profile
		if profile == nil or not profile:IsActive() then
			return false
		end

		local success = pcall(function()
			profile:Save()
		end)
		if not success then
			return false
		end

		return true
	end)
end

function PlayerDataServiceServer.SaveAllPlayerData(self: PlayerDataServiceServer)
	for player in self.playerRuntimes do
		self:SavePlayerData(player)
	end
end

function PlayerDataServiceServer.Destroy(self: PlayerDataServiceServer)
	if self.playerAddedConnection then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end

	if self.playerRemovingConnection then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end

	for player, runtime in self.playerRuntimes do
		self.playerRuntimes[player] = nil
		runtime.loadToken += 1
		if runtime.loadPromise ~= nil then
			runtime.loadPromise:Destroy()
			runtime.loadPromise = nil
		end
		runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_UNLOADED
		self:EmitRuntimeStateChanged(runtime)
		self:ReleaseProfile(runtime)
		runtime.stateChangedSignal:Destroy()
	end
end
type PlayerDataServiceServer = typeof(PlayerDataServiceServer) & {
	profileStore: ProfileStoreObject,
	dataTemplate: PlayerData,
	playerRuntimes: { [Player]: PlayerRuntime },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return PlayerDataServiceServer :: PlayerDataServiceServer
