--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Signal = require(ReplicatedStorage.Packages.Signal)
local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)
local PlayerDataServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.PlayerDataService.PlayerDataServiceUtils)
local DataTemplate = require(script:FindFirstAncestor("game").Shared.Modules.Core.DataTemplate)
local Promise = require("Promise")
local ProfileStore = require(game:GetService("ServerScriptService"):WaitForChild("ServerPackages"):WaitForChild("ProfileStore"))

type PlayerData = PlayerDataServiceUtils.PlayerData
type LoadState = PlayerDataServiceUtils.LoadState
type Profile = ProfileStore.Profile<PlayerData>
type ProfileStoreObject = ProfileStore.ProfileStore<PlayerData>
type ProfileSignalConnection = {
	Disconnect: (self: ProfileSignalConnection) -> (),
}

type StateChangedSignal = {
	Connect: (self: StateChangedSignal, callback: () -> ()) -> any,
	Fire: (self: StateChangedSignal) -> (),
	DisconnectAll: (self: StateChangedSignal) -> (),
	Destroy: (self: StateChangedSignal) -> (),
}

type PlayerRuntime = {
	loadToken: number,
	loadState: LoadState,
	profile: Profile?,
	data: PlayerData?,
	isLoading: boolean,
	hasResolvedInitialLoad: boolean,
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

local DATA_SESSION_ENDED_KICK_MESSAGE = "Your data session ended. Please rejoin."
local PROFILE_FALLBACK_DATASTORE_TIMEOUT_SECONDS = 2
local PROFILE_SESSION_START_TIMEOUT_SECONDS = 5

local function promiseTry<T...>(callback: () -> T...): Promise.Promise<T...>
	return Promise.spawn(function(resolve, reject)
		local results = table.pack(pcall(callback))
		if results[1] then
			resolve(table.unpack(results, 2, results.n))
		else
			reject(table.unpack(results, 2, results.n))
		end
	end)
end

local function resolvePlayerDataTemplate(): PlayerData
	local templateRoot = if typeof(DataTemplate) == "table" then DataTemplate else {}
	local playerData = if typeof((templateRoot :: any).playerData) == "table" then (templateRoot :: any).playerData else {}
	return PlayerDataServiceUtils.createDefaultData(playerData)
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

local function sanitizeFailureReason(reasonRaw: any): string?
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

function PlayerDataServiceServer.Init(self: PlayerDataServiceServer)
	self.dataTemplate = resolvePlayerDataTemplate()
	self.profileStore = ProfileStore.New(PlayerDataServiceUtils.DEFAULT_PROFILE_STORE_NAME, self.dataTemplate)
	self.playerRuntimes = {}
	self.networker = Networker.server.new("PlayerDataService", self, {
		self.RequestSync,
	})

	for _, player in Players:GetPlayers() do
		self:trackPlayer(player)
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self:trackPlayer(player)
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:untrackPlayer(player)
	end)
end

function PlayerDataServiceServer.CreateRuntime(_self: PlayerDataServiceServer): PlayerRuntime
	return {
		loadToken = 0,
		loadState = PlayerDataServiceUtils.LOAD_STATE_UNLOADED,
		profile = nil,
		data = nil,
		isLoading = false,
		hasResolvedInitialLoad = false,
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

	local nextRuntime = self:createRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function PlayerDataServiceServer.GetRuntimeLoadElapsedSeconds(_self: PlayerDataServiceServer, runtime: PlayerRuntime): number
	if runtime.loadStartedAt <= 0 then
		return 0
	end
	return math.max(0, os.clock() - runtime.loadStartedAt)
end

function PlayerDataServiceServer.GetRuntimeStateMetadata(
	self: PlayerDataServiceServer,
	runtime: PlayerRuntime
): { [string]: any }
	return {
		isLoading = runtime.isLoading,
		hasResolvedInitialLoad = runtime.hasResolvedInitialLoad,
		loadToken = runtime.loadToken,
		lastFailureReason = runtime.lastFailureReason,
		loadElapsedSeconds = self:getRuntimeLoadElapsedSeconds(runtime),
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
		fields[#fields + 1] = ("hasResolvedInitialLoad=%s"):format(tostring(runtime.hasResolvedInitialLoad))
		fields[#fields + 1] = ("loadToken=%d"):format(runtime.loadToken)
		fields[#fields + 1] = ("elapsed=%.3f"):format(self:getRuntimeLoadElapsedSeconds(runtime))
		if runtime.lastFailureReason ~= nil then
			fields[#fields + 1] = ("lastFailureReason=%s"):format(runtime.lastFailureReason)
		end
	end
	if typeof(extraFieldsRaw) == "table" then
		for key, value in (extraFieldsRaw :: { [string]: any }) do
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
	self:disconnectProfileEndedConnection(runtime)

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
	if self.networker == nil then
		if runtime ~= nil then
			self:emitRuntimeStateChanged(runtime)
		end
		return
	end

	if runtime == nil then
		self.networker:fire(player, "applyState", nil, PlayerDataServiceUtils.LOAD_STATE_UNLOADED, {
			isLoading = false,
			hasResolvedInitialLoad = false,
			loadToken = 0,
			lastFailureReason = nil,
			loadElapsedSeconds = 0,
		})
		return
	end

	local dataSnapshot = if runtime.data ~= nil then PlayerDataServiceUtils.cloneDeep(runtime.data) else nil
	self.networker:fire(player, "applyState", dataSnapshot, runtime.loadState, self:getRuntimeStateMetadata(runtime))
	self:emitRuntimeStateChanged(runtime)
end

function PlayerDataServiceServer.GetResolvedRuntime(self: PlayerDataServiceServer, player: Player): PlayerRuntime?
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
	if runtime.hasResolvedInitialLoad then
		return runtime
	end
	return nil
end

function PlayerDataServiceServer.ResolvePersistedDataSnapshot(
	self: PlayerDataServiceServer,
	rawSnapshotRaw: any
): PlayerData
	local rawSnapshot = rawSnapshotRaw
	if typeof(rawSnapshot) == "table" and typeof((rawSnapshot :: { [string]: any }).Data) == "table" then
		rawSnapshot = (rawSnapshot :: { [string]: any }).Data
	end

	local resolved = if typeof(rawSnapshot) == "table"
		then PlayerDataServiceUtils.cloneDeep(rawSnapshot)
		else PlayerDataServiceUtils.createDefaultData(self.dataTemplate)
	PlayerDataServiceUtils.reconcileData(resolved, self.dataTemplate)
	return resolved
end

function PlayerDataServiceServer.ResolveFallbackLoadResult(
	self: PlayerDataServiceServer,
	player: Player
): (boolean, PlayerData?, string, string)
	local profileKey = PlayerDataServiceUtils.getProfileKey(player)
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
		self:resolvePersistedDataSnapshot(rawSnapshot),
		if rawSnapshot == nil then "default" else "datastore",
		if rawSnapshot == nil then "fallback_default_data" else "fallback_datastore"
end

function PlayerDataServiceServer.StartProfileLoad(self: PlayerDataServiceServer, player: Player, runtime: PlayerRuntime)
	local currentLoadToken = runtime.loadToken
	if runtime.loadPromise ~= nil then
		return
	end

	runtime.loadPromise = self:loadProfilePromise(player, currentLoadToken):Finally(function()
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

	local resolvedData = self:resolvePersistedDataSnapshot(dataRaw)
	self:disconnectProfileEndedConnection(runtime)
	runtime.profile = profileRaw
	runtime.data = resolvedData
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_LOADED
	runtime.isLoading = false
	runtime.hasResolvedInitialLoad = true
	runtime.lastFailureReason = nil
	runtime.usingFallbackData = runtime.profile == nil
	runtime.fallbackBaselineData = if runtime.usingFallbackData then PlayerDataServiceUtils.cloneDeep(resolvedData) else nil
	runtime.fallbackDirty = false
	if runtime.profile ~= nil then
		local activeProfile = runtime.profile :: Profile
		runtime.profileEndedConnection = activeProfile.OnSessionEnd:Connect(function()
			self:onProfileSessionEnded(player, activeProfile)
		end)
	end
	self:pushState(player)
	self:logEvent("load_success", player, runtime, {
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

	self:disconnectProfileEndedConnection(runtime)
	runtime.profile = nil
	runtime.data = PlayerDataServiceUtils.createDefaultData(self.dataTemplate)
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_FAILED
	runtime.isLoading = false
	runtime.hasResolvedInitialLoad = true
	runtime.lastFailureReason = sanitizeFailureReason(reasonRaw) or "unknown"
	runtime.usingFallbackData = false
	runtime.fallbackBaselineData = nil
	runtime.fallbackDirty = false
	self:pushState(player)
	self:logEvent("load_failed_terminal", player, runtime, {
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

	self:disconnectProfileEndedConnection(runtime)
	runtime.profile = nil
	runtime.data = PlayerDataServiceUtils.createDefaultData(self.dataTemplate)
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_FAILED
	runtime.isLoading = false
	runtime.hasResolvedInitialLoad = true
	runtime.lastFailureReason = "session_ended"
	runtime.usingFallbackData = false
	runtime.fallbackBaselineData = nil
	runtime.fallbackDirty = false
	self:pushState(player)

	if player.Parent == Players and not ProfileStore.IsClosing then
		player:Kick(DATA_SESSION_ENDED_KICK_MESSAGE)
	end
end

function PlayerDataServiceServer.LoadProfilePromise(
	self: PlayerDataServiceServer,
	player: Player,
	loadToken: number
)
	return promiseTry(function()
		local runtime = self.playerRuntimes[player]
		if runtime == nil or runtime.loadToken ~= loadToken then
			return nil
		end
		self:logEvent("load_begin", player, runtime, nil)

		local profileKey = PlayerDataServiceUtils.getProfileKey(player)
		if profileKey == nil then
			self:finalizeFailedRuntime(player, runtime, loadToken, "profile_key_invalid")
			return nil
		end

		local loadDeadline = os.clock() + PROFILE_SESSION_START_TIMEOUT_SECONDS
		local profile: Profile? = nil
		local success, resultOrError = pcall(function()
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
			local fallbackSuccess, fallbackData, fallbackSource, fallbackReason = self:resolveFallbackLoadResult(player)
			runtime = self.playerRuntimes[player]
			if runtime == nil or runtime.loadToken ~= loadToken then
				return nil
			end
			if fallbackSuccess and fallbackData ~= nil then
				self:finalizeLoadedRuntime(
					player,
					runtime,
					loadToken,
					fallbackData,
					fallbackSource,
					primaryFailureReason .. "|" .. fallbackReason,
					nil
				)
				return fallbackData
			end
			self:finalizeFailedRuntime(player, runtime, loadToken, primaryFailureReason .. "|" .. fallbackReason)
			return nil
		end

		profile:AddUserId(player.UserId)
		profile:Reconcile()

		local profileData = profile.Data
		if typeof(profileData) ~= "table" then
			profileData = PlayerDataServiceUtils.createDefaultData(self.dataTemplate)
			profile.Data = profileData
		end
		PlayerDataServiceUtils.reconcileData(profileData, self.dataTemplate)
		self:finalizeLoadedRuntime(player, runtime, loadToken, profileData, "profile", "profile_loaded", profile)
		return profileData
	end):Catch(function(err: any)
		local runtime = self.playerRuntimes[player]
		if runtime ~= nil and runtime.loadToken == loadToken then
			self:finalizeFailedRuntime(player, runtime, loadToken, "unexpected_error:" .. tostring(err))
		end
		return nil
	end)
end

function PlayerDataServiceServer.TrackPlayer(self: PlayerDataServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	if runtime.isLoading or runtime.hasResolvedInitialLoad then
		self:pushState(player)
		return
	end
	runtime.loadToken += 1
	self:releaseProfile(runtime)
	runtime.data = nil
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_LOADING
	runtime.isLoading = true
	runtime.hasResolvedInitialLoad = false
	runtime.lastFailureReason = nil
	runtime.loadStartedAt = os.clock()
	runtime.usingFallbackData = false
	runtime.fallbackBaselineData = nil
	runtime.fallbackDirty = false
	self:logEvent("trackPlayer_start", player, runtime, nil)
	self:pushState(player)
	self:startProfileLoad(player, runtime)
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
	runtime.hasResolvedInitialLoad = false
	runtime.lastFailureReason = nil
	runtime.loadStartedAt = 0
	self:emitRuntimeStateChanged(runtime)
	self.playerRuntimes[player] = nil
	self:releaseProfile(runtime)
	runtime.stateChangedSignal:Destroy()
end

function PlayerDataServiceServer.GetActiveRuntime(self: PlayerDataServiceServer, player: Player): PlayerRuntime?
	local runtime = self:getResolvedRuntime(player)
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
		self:trackPlayer(player)
		return
	end

	self:pushState(player)
end

function PlayerDataServiceServer.GetLoadState(self: PlayerDataServiceServer, player: Player): LoadState
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return PlayerDataServiceUtils.LOAD_STATE_UNLOADED
	end
	return runtime.loadState
end

function PlayerDataServiceServer.IsLoaded(self: PlayerDataServiceServer, player: Player): boolean
	return self:getResolvedRuntime(player) ~= nil
end

function PlayerDataServiceServer.WaitForData(
	self: PlayerDataServiceServer,
	player: Player,
	timeoutSecondsRaw: any
): PlayerData?
	local success, result = self:waitForDataPromise(player, timeoutSecondsRaw):Yield()
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

	local function resolveIfReady(): PlayerData?
		local availableRuntime = self:getAvailableRuntime(player)
		if availableRuntime ~= nil and availableRuntime.data ~= nil then
			return availableRuntime.data
		end
		return nil
	end

	local immediateData = resolveIfReady()
	if immediateData ~= nil then
		return Promise.resolved(immediateData)
	end

	local trackedRuntime = self.playerRuntimes[player]
	if trackedRuntime == nil then
		return Promise.resolved(nil)
	end
	if trackedRuntime.hasResolvedInitialLoad then
		return Promise.resolved(resolveIfReady())
	end

	if timeoutSeconds <= 0 then
		return Promise.resolved(nil)
	end

	return Promise.new(function(resolve, _reject)
		local connection = nil
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
			resolve(result)
		end

		connection = trackedRuntime.stateChangedSignal:Connect(function()
			local currentRuntime = self.playerRuntimes[player]
			if currentRuntime == nil or currentRuntime.hasResolvedInitialLoad or resolveIfReady() ~= nil then
				settle(resolveIfReady())
			end
		end)

		local readyData = resolveIfReady()
		if readyData ~= nil or trackedRuntime.hasResolvedInitialLoad then
			settle(readyData)
			return
		end

		task.delay(timeoutSeconds, function()
			settle(nil)
		end)
	end)
end

function PlayerDataServiceServer.GetProfile(self: PlayerDataServiceServer, player: Player): Profile?
	local runtime = self:getActiveRuntime(player)
	if runtime == nil then
		return nil
	end
	return runtime.profile
end

function PlayerDataServiceServer.GetData(self: PlayerDataServiceServer, player: Player): PlayerData?
	local runtime = self:getAvailableRuntime(player)
	if runtime == nil then
		return nil
	end
	return runtime.data
end

function PlayerDataServiceServer.GetDataCopy(self: PlayerDataServiceServer, player: Player): PlayerData?
	local data = self:getData(player)
	if data == nil then
		return nil
	end
	return PlayerDataServiceUtils.cloneDeep(data)
end

function PlayerDataServiceServer.GetValue(
	self: PlayerDataServiceServer,
	player: Player,
	pathRaw: any,
	fallback: any
): any
	local data = self:getData(player)
	if data == nil then
		return fallback
	end
	return PlayerDataServiceUtils.getValueAtPath(data, pathRaw, fallback)
end

function PlayerDataServiceServer.GetHpData(self: PlayerDataServiceServer, player: Player, fallback: any): any
	return self:getValue(player, PlayerDataServiceUtils.getDefaultHpDataPath(), fallback)
end

function PlayerDataServiceServer.GetCoinsData(self: PlayerDataServiceServer, player: Player, fallback: any): any
	return self:getValue(player, PlayerDataServiceUtils.getDefaultCoinsDataPath(), fallback)
end

function PlayerDataServiceServer.SetValue(
	self: PlayerDataServiceServer,
	player: Player,
	pathRaw: any,
	value: any,
	replicateToClientRaw: any
): boolean
	local runtime = self:getResolvedRuntime(player)
	if runtime == nil or runtime.data == nil then
		return false
	end

	local didSet = PlayerDataServiceUtils.setValueAtPath(runtime.data, pathRaw, value)
	if didSet and runtime.usingFallbackData then
		runtime.fallbackDirty = true
	end
	if didSet and replicateToClientRaw ~= false then
		self:pushState(player)
	end
	return didSet
end

function PlayerDataServiceServer.SetHpData(
	self: PlayerDataServiceServer,
	player: Player,
	hpDataRaw: any,
	replicateToClientRaw: any
): boolean
	return self:setValue(player, PlayerDataServiceUtils.getDefaultHpDataPath(), hpDataRaw, replicateToClientRaw)
end

function PlayerDataServiceServer.SetCoinsData(
	self: PlayerDataServiceServer,
	player: Player,
	coinsDataRaw: any,
	replicateToClientRaw: any
): boolean
	return self:setValue(player, PlayerDataServiceUtils.getDefaultCoinsDataPath(), coinsDataRaw, replicateToClientRaw)
end

function PlayerDataServiceServer.RemoveValue(
	self: PlayerDataServiceServer,
	player: Player,
	pathRaw: any,
	replicateToClientRaw: any
): boolean
	local runtime = self:getResolvedRuntime(player)
	if runtime == nil or runtime.data == nil then
		return false
	end

	local didRemove = PlayerDataServiceUtils.removeValueAtPath(runtime.data, pathRaw)
	if didRemove and runtime.usingFallbackData then
		runtime.fallbackDirty = true
	end
	if didRemove and replicateToClientRaw ~= false then
		self:pushState(player)
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
	local runtime = self:getResolvedRuntime(player)
	if runtime == nil or runtime.data == nil then
		return nil
	end

	local nextValue =
		PlayerDataServiceUtils.incrementValueAtPath(runtime.data, pathRaw, amountRaw, fallbackValueRaw)
	if nextValue ~= nil and runtime.usingFallbackData then
		runtime.fallbackDirty = true
	end
	if nextValue ~= nil and replicateToClientRaw ~= false then
		self:pushState(player)
	end
	return nextValue
end

function PlayerDataServiceServer.MergeData(
	self: PlayerDataServiceServer,
	player: Player,
	incomingDataRaw: any,
	replicateToClientRaw: any
): boolean
	local runtime = self:getResolvedRuntime(player)
	if runtime == nil or runtime.data == nil then
		return false
	end

	local didMerge = PlayerDataServiceUtils.mergeData(runtime.data, incomingDataRaw)
	if didMerge and runtime.usingFallbackData then
		runtime.fallbackDirty = true
	end
	if didMerge and replicateToClientRaw ~= false then
		self:pushState(player)
	end
	return didMerge
end

function PlayerDataServiceServer.SavePlayerData(self: PlayerDataServiceServer, player: Player): boolean
	local success, result = self:savePlayerDataPromise(player):Yield()
	if not success then
		return false
	end
	return result == true
end

function PlayerDataServiceServer.SavePlayerDataPromise(self: PlayerDataServiceServer, player: Player)
	return promiseTry(function()
		local runtime = self:getActiveRuntime(player)
		if runtime == nil then
			return false
		end

		local profile = runtime.profile
		if profile == nil or not profile:IsActive() then
			return false
		end

		local success, resultOrError = pcall(function()
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
		self:savePlayerData(player)
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
		self:emitRuntimeStateChanged(runtime)
		self:releaseProfile(runtime)
		runtime.stateChangedSignal:Destroy()
	end

	if self.networker then
		self.networker:destroy()
	end
end

PlayerDataServiceServer.init = PlayerDataServiceServer.Init
PlayerDataServiceServer.createRuntime = PlayerDataServiceServer.CreateRuntime
PlayerDataServiceServer.getRuntime = PlayerDataServiceServer.GetRuntime
PlayerDataServiceServer.getRuntimeLoadElapsedSeconds = PlayerDataServiceServer.GetRuntimeLoadElapsedSeconds
PlayerDataServiceServer.getRuntimeStateMetadata = PlayerDataServiceServer.GetRuntimeStateMetadata
PlayerDataServiceServer.logEvent = PlayerDataServiceServer.LogEvent
PlayerDataServiceServer.disconnectProfileEndedConnection = PlayerDataServiceServer.DisconnectProfileEndedConnection
PlayerDataServiceServer.releaseProfile = PlayerDataServiceServer.ReleaseProfile
PlayerDataServiceServer.emitRuntimeStateChanged = PlayerDataServiceServer.EmitRuntimeStateChanged
PlayerDataServiceServer.pushState = PlayerDataServiceServer.PushState
PlayerDataServiceServer.getResolvedRuntime = PlayerDataServiceServer.GetResolvedRuntime
PlayerDataServiceServer.getAvailableRuntime = PlayerDataServiceServer.GetAvailableRuntime
PlayerDataServiceServer.resolvePersistedDataSnapshot = PlayerDataServiceServer.ResolvePersistedDataSnapshot
PlayerDataServiceServer.resolveFallbackLoadResult = PlayerDataServiceServer.ResolveFallbackLoadResult
PlayerDataServiceServer.startProfileLoad = PlayerDataServiceServer.StartProfileLoad
PlayerDataServiceServer.finalizeLoadedRuntime = PlayerDataServiceServer.FinalizeLoadedRuntime
PlayerDataServiceServer.finalizeFailedRuntime = PlayerDataServiceServer.FinalizeFailedRuntime
PlayerDataServiceServer.onProfileSessionEnded = PlayerDataServiceServer.OnProfileSessionEnded
PlayerDataServiceServer.loadProfilePromise = PlayerDataServiceServer.LoadProfilePromise
PlayerDataServiceServer.trackPlayer = PlayerDataServiceServer.TrackPlayer
PlayerDataServiceServer.untrackPlayer = PlayerDataServiceServer.UntrackPlayer
PlayerDataServiceServer.getActiveRuntime = PlayerDataServiceServer.GetActiveRuntime
PlayerDataServiceServer.requestSync = PlayerDataServiceServer.RequestSync
PlayerDataServiceServer.getLoadState = PlayerDataServiceServer.GetLoadState
PlayerDataServiceServer.isLoaded = PlayerDataServiceServer.IsLoaded
PlayerDataServiceServer.waitForData = PlayerDataServiceServer.WaitForData
PlayerDataServiceServer.waitForDataPromise = PlayerDataServiceServer.WaitForDataPromise
PlayerDataServiceServer.getProfile = PlayerDataServiceServer.GetProfile
PlayerDataServiceServer.getData = PlayerDataServiceServer.GetData
PlayerDataServiceServer.getDataCopy = PlayerDataServiceServer.GetDataCopy
PlayerDataServiceServer.getValue = PlayerDataServiceServer.GetValue
PlayerDataServiceServer.getHpData = PlayerDataServiceServer.GetHpData
PlayerDataServiceServer.getCoinsData = PlayerDataServiceServer.GetCoinsData
PlayerDataServiceServer.setValue = PlayerDataServiceServer.SetValue
PlayerDataServiceServer.setHpData = PlayerDataServiceServer.SetHpData
PlayerDataServiceServer.setCoinsData = PlayerDataServiceServer.SetCoinsData
PlayerDataServiceServer.removeValue = PlayerDataServiceServer.RemoveValue
PlayerDataServiceServer.incrementValue = PlayerDataServiceServer.IncrementValue
PlayerDataServiceServer.mergeData = PlayerDataServiceServer.MergeData
PlayerDataServiceServer.savePlayerData = PlayerDataServiceServer.SavePlayerData
PlayerDataServiceServer.savePlayerDataPromise = PlayerDataServiceServer.SavePlayerDataPromise
PlayerDataServiceServer.saveAllPlayerData = PlayerDataServiceServer.SaveAllPlayerData
PlayerDataServiceServer.destroy = PlayerDataServiceServer.Destroy

type PlayerDataServiceServer = typeof(PlayerDataServiceServer) & {
	networker: Networker.Server,
	profileStore: ProfileStoreObject,
	dataTemplate: PlayerData,
	playerRuntimes: { [Player]: PlayerRuntime },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return PlayerDataServiceServer :: PlayerDataServiceServer
