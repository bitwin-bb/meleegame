--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Promise = require(ReplicatedStorage.Packages.Promise)
local ProfileStore = require(ReplicatedStorage.Packages.ProfileStore)
local Signal = require(ReplicatedStorage.Packages.Signal)
local PlayerDataServiceUtils = require(ReplicatedStorage.Shared.Services.PlayerDataService.PlayerDataServiceUtils)
local DataTemplate = require(ReplicatedStorage.Shared.Modules.Core.DataTemplate)

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
	profileEndedConnection: ProfileSignalConnection?,
	stateChangedSignal: StateChangedSignal,
	loadPromise: any?,
}

local PlayerDataServiceServer = {}

local DATA_LOAD_FAILED_KICK_MESSAGE = "Unable to load your data. Please rejoin."
local DATA_SESSION_ENDED_KICK_MESSAGE = "Your data session ended. Please rejoin."
-- ProfileStore's default session-start timeout is 120 seconds, but providing
-- a Cancel callback disables that fallback. Mirror the default here so we keep
-- leave/load-token cancellation without allowing live joins to hang forever.
local PROFILE_SESSION_START_TIMEOUT_SECONDS = 120

local function resolvePlayerDataTemplate(): PlayerData
	local templateRoot = if typeof(DataTemplate) == "table" then DataTemplate else {}
	local playerData = if typeof((templateRoot :: any).playerData) == "table" then (templateRoot :: any).playerData else {}
	return PlayerDataServiceUtils.createDefaultData(playerData)
end

function PlayerDataServiceServer.init(self: PlayerDataServiceServer)
	self.dataTemplate = resolvePlayerDataTemplate()
	self.profileStore = ProfileStore.New(PlayerDataServiceUtils.DEFAULT_PROFILE_STORE_NAME, self.dataTemplate)
	self.playerRuntimes = {}
	self.networker = Networker.server.new("PlayerDataService", self, {
		self.requestSync,
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

function PlayerDataServiceServer.createRuntime(self: PlayerDataServiceServer): PlayerRuntime
	return {
		loadToken = 0,
		loadState = PlayerDataServiceUtils.LOAD_STATE_UNLOADED,
		profile = nil,
		data = nil,
		profileEndedConnection = nil,
		stateChangedSignal = Signal.new() :: StateChangedSignal,
		loadPromise = nil,
	}
end

function PlayerDataServiceServer.getRuntime(self: PlayerDataServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime then
		return runtime
	end

	local nextRuntime = self:createRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function PlayerDataServiceServer.disconnectProfileEndedConnection(
	self: PlayerDataServiceServer,
	runtime: PlayerRuntime
)
	local connection = runtime.profileEndedConnection
	if connection == nil then
		return
	end

	connection:Disconnect()
	runtime.profileEndedConnection = nil
end

function PlayerDataServiceServer.releaseProfile(self: PlayerDataServiceServer, runtime: PlayerRuntime)
	self:disconnectProfileEndedConnection(runtime)

	local profile = runtime.profile
	runtime.profile = nil
	runtime.data = nil

	if profile and profile:IsActive() then
		profile:EndSession()
	end
end

function PlayerDataServiceServer.emitRuntimeStateChanged(self: PlayerDataServiceServer, runtime: PlayerRuntime)
	runtime.stateChangedSignal:Fire()
end

function PlayerDataServiceServer.pushState(self: PlayerDataServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if self.networker == nil then
		if runtime ~= nil then
			self:emitRuntimeStateChanged(runtime)
		end
		return
	end

	if runtime == nil then
		self.networker:fire(player, "applyState", nil, PlayerDataServiceUtils.LOAD_STATE_UNLOADED)
		return
	end

	local dataSnapshot = if runtime.data ~= nil then PlayerDataServiceUtils.cloneDeep(runtime.data) else nil
	self.networker:fire(player, "applyState", dataSnapshot, runtime.loadState)
	self:emitRuntimeStateChanged(runtime)
end

function PlayerDataServiceServer.onProfileSessionEnded(self: PlayerDataServiceServer, player: Player, profile: Profile)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end
	if runtime.profile ~= profile then
		return
	end

	self:disconnectProfileEndedConnection(runtime)
	runtime.profile = nil
	runtime.data = nil
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_FAILED
	self:pushState(player)

	if player.Parent == Players and not ProfileStore.IsClosing then
		player:Kick(DATA_SESSION_ENDED_KICK_MESSAGE)
	end
end

function PlayerDataServiceServer.loadProfilePromise(
	self: PlayerDataServiceServer,
	player: Player,
	loadToken: number
)
	return Promise.try(function()
		local runtime = self.playerRuntimes[player]
		if runtime == nil or runtime.loadToken ~= loadToken then
			return nil
		end

		local profileKey = PlayerDataServiceUtils.getProfileKey(player)
		if profileKey == nil then
			runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_FAILED
			self:pushState(player)
			if player.Parent == Players and not ProfileStore.IsClosing then
				player:Kick(DATA_LOAD_FAILED_KICK_MESSAGE)
			end
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
		else
			warn(("[PlayerDataService] Failed to start profile for %s (%d): %s"):format(
				player.Name,
				player.UserId,
				tostring(resultOrError)
			))
		end

		runtime = self.playerRuntimes[player]
		if runtime == nil or runtime.loadToken ~= loadToken then
			if profile and profile:IsActive() then
				profile:EndSession()
			end
			return nil
		end

		if profile == nil then
			if os.clock() >= loadDeadline then
				warn(("[PlayerDataService] Timed out starting a profile session for %s (%d)."):format(
					player.Name,
					player.UserId
				))
			end

			runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_FAILED
			self:pushState(player)
			if player.Parent == Players and not ProfileStore.IsClosing then
				player:Kick(DATA_LOAD_FAILED_KICK_MESSAGE)
			end
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

		self:disconnectProfileEndedConnection(runtime)
		runtime.profile = profile
		runtime.data = profileData
		runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_LOADED
		runtime.profileEndedConnection = profile.OnSessionEnd:Connect(function()
			self:onProfileSessionEnded(player, profile :: Profile)
		end)

		self:pushState(player)
		return profileData
	end):catch(function(err: any)
		warn(("[PlayerDataService] Unexpected loadProfilePromise failure for %s (%d): %s"):format(
			player.Name,
			player.UserId,
			tostring(err)
		))

		local runtime = self.playerRuntimes[player]
		if runtime ~= nil and runtime.loadToken == loadToken then
			runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_FAILED
			self:pushState(player)
		end
		if player.Parent == Players and not ProfileStore.IsClosing then
			player:Kick(DATA_LOAD_FAILED_KICK_MESSAGE)
		end
		return nil
	end)
end

function PlayerDataServiceServer.trackPlayer(self: PlayerDataServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	runtime.loadToken += 1
	if runtime.loadPromise ~= nil then
		runtime.loadPromise:cancel()
		runtime.loadPromise = nil
	end
	self:releaseProfile(runtime)
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_LOADING
	self:pushState(player)

	local currentLoadToken = runtime.loadToken
	runtime.loadPromise = self:loadProfilePromise(player, currentLoadToken):finally(function()
		local currentRuntime = self.playerRuntimes[player]
		if currentRuntime ~= nil and currentRuntime.loadToken == currentLoadToken then
			currentRuntime.loadPromise = nil
		end
	end)
end

function PlayerDataServiceServer.untrackPlayer(self: PlayerDataServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	runtime.loadToken += 1
	if runtime.loadPromise ~= nil then
		runtime.loadPromise:cancel()
		runtime.loadPromise = nil
	end
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_UNLOADED
	self:emitRuntimeStateChanged(runtime)
	self.playerRuntimes[player] = nil
	self:releaseProfile(runtime)
	runtime.stateChangedSignal:Destroy()
end

function PlayerDataServiceServer.getActiveRuntime(self: PlayerDataServiceServer, player: Player): PlayerRuntime?
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

	local profile = runtime.profile
	if profile == nil or not profile:IsActive() then
		return nil
	end

	return runtime
end

function PlayerDataServiceServer.requestSync(self: PlayerDataServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		self:trackPlayer(player)
		return
	end
	self:pushState(player)
end

function PlayerDataServiceServer.getLoadState(self: PlayerDataServiceServer, player: Player): LoadState
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return PlayerDataServiceUtils.LOAD_STATE_UNLOADED
	end
	return runtime.loadState
end

function PlayerDataServiceServer.isLoaded(self: PlayerDataServiceServer, player: Player): boolean
	return self:getActiveRuntime(player) ~= nil
end

function PlayerDataServiceServer.waitForData(
	self: PlayerDataServiceServer,
	player: Player,
	timeoutSecondsRaw: any
): PlayerData?
	local success, result = self:waitForDataPromise(player, timeoutSecondsRaw):await()
	if not success then
		return nil
	end
	return result :: PlayerData?
end

function PlayerDataServiceServer.waitForDataPromise(
	self: PlayerDataServiceServer,
	player: Player,
	timeoutSecondsRaw: any
)
	local timeoutSeconds = if typeof(timeoutSecondsRaw) == "number" and timeoutSecondsRaw == timeoutSecondsRaw
		then math.max(0, timeoutSecondsRaw)
		else 15

	local function resolveIfReady(): PlayerData?
		local activeRuntime = self:getActiveRuntime(player)
		if activeRuntime ~= nil and activeRuntime.data ~= nil then
			return activeRuntime.data
		end
		return nil
	end

	local immediateData = resolveIfReady()
	if immediateData ~= nil then
		return Promise.resolve(immediateData)
	end

	local trackedRuntime = self.playerRuntimes[player]
	if trackedRuntime == nil then
		return Promise.resolve(nil)
	end
	if trackedRuntime.loadState == PlayerDataServiceUtils.LOAD_STATE_FAILED then
		return Promise.resolve(nil)
	end

	local stateChangedPromise = Promise.fromEvent(trackedRuntime.stateChangedSignal, function()
		local currentRuntime = self.playerRuntimes[player]
		if currentRuntime == nil then
			return true
		end
		if currentRuntime.loadState == PlayerDataServiceUtils.LOAD_STATE_FAILED then
			return true
		end
		return resolveIfReady() ~= nil
	end):andThen(function()
		return resolveIfReady()
	end)

	if timeoutSeconds <= 0 then
		return Promise.resolve(nil)
	end

	return Promise.race({
		stateChangedPromise,
		Promise.delay(timeoutSeconds):andThen(function()
			return nil
		end),
	})
end

function PlayerDataServiceServer.getProfile(self: PlayerDataServiceServer, player: Player): Profile?
	local runtime = self:getActiveRuntime(player)
	if runtime == nil then
		return nil
	end
	return runtime.profile
end

function PlayerDataServiceServer.getData(self: PlayerDataServiceServer, player: Player): PlayerData?
	local runtime = self:getActiveRuntime(player)
	if runtime == nil then
		return nil
	end
	return runtime.data
end

function PlayerDataServiceServer.getDataCopy(self: PlayerDataServiceServer, player: Player): PlayerData?
	local data = self:getData(player)
	if data == nil then
		return nil
	end
	return PlayerDataServiceUtils.cloneDeep(data)
end

function PlayerDataServiceServer.getValue(
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

function PlayerDataServiceServer.getHpData(self: PlayerDataServiceServer, player: Player, fallback: any): any
	return self:getValue(player, PlayerDataServiceUtils.getDefaultHpDataPath(), fallback)
end

function PlayerDataServiceServer.getCoinsData(self: PlayerDataServiceServer, player: Player, fallback: any): any
	return self:getValue(player, PlayerDataServiceUtils.getDefaultCoinsDataPath(), fallback)
end

function PlayerDataServiceServer.setValue(
	self: PlayerDataServiceServer,
	player: Player,
	pathRaw: any,
	value: any,
	replicateToClientRaw: any
): boolean
	local runtime = self:getActiveRuntime(player)
	if runtime == nil or runtime.data == nil then
		return false
	end

	local didSet = PlayerDataServiceUtils.setValueAtPath(runtime.data, pathRaw, value)
	if didSet and replicateToClientRaw ~= false then
		self:pushState(player)
	end
	return didSet
end

function PlayerDataServiceServer.setHpData(
	self: PlayerDataServiceServer,
	player: Player,
	hpDataRaw: any,
	replicateToClientRaw: any
): boolean
	return self:setValue(player, PlayerDataServiceUtils.getDefaultHpDataPath(), hpDataRaw, replicateToClientRaw)
end

function PlayerDataServiceServer.setCoinsData(
	self: PlayerDataServiceServer,
	player: Player,
	coinsDataRaw: any,
	replicateToClientRaw: any
): boolean
	return self:setValue(player, PlayerDataServiceUtils.getDefaultCoinsDataPath(), coinsDataRaw, replicateToClientRaw)
end

function PlayerDataServiceServer.removeValue(
	self: PlayerDataServiceServer,
	player: Player,
	pathRaw: any,
	replicateToClientRaw: any
): boolean
	local runtime = self:getActiveRuntime(player)
	if runtime == nil or runtime.data == nil then
		return false
	end

	local didRemove = PlayerDataServiceUtils.removeValueAtPath(runtime.data, pathRaw)
	if didRemove and replicateToClientRaw ~= false then
		self:pushState(player)
	end
	return didRemove
end

function PlayerDataServiceServer.incrementValue(
	self: PlayerDataServiceServer,
	player: Player,
	pathRaw: any,
	amountRaw: any,
	fallbackValueRaw: any,
	replicateToClientRaw: any
): number?
	local runtime = self:getActiveRuntime(player)
	if runtime == nil or runtime.data == nil then
		return nil
	end

	local nextValue =
		PlayerDataServiceUtils.incrementValueAtPath(runtime.data, pathRaw, amountRaw, fallbackValueRaw)
	if nextValue ~= nil and replicateToClientRaw ~= false then
		self:pushState(player)
	end
	return nextValue
end

function PlayerDataServiceServer.mergeData(
	self: PlayerDataServiceServer,
	player: Player,
	incomingDataRaw: any,
	replicateToClientRaw: any
): boolean
	local runtime = self:getActiveRuntime(player)
	if runtime == nil or runtime.data == nil then
		return false
	end

	local didMerge = PlayerDataServiceUtils.mergeData(runtime.data, incomingDataRaw)
	if didMerge and replicateToClientRaw ~= false then
		self:pushState(player)
	end
	return didMerge
end

function PlayerDataServiceServer.savePlayerData(self: PlayerDataServiceServer, player: Player): boolean
	local success, result = self:savePlayerDataPromise(player):await()
	if not success then
		return false
	end
	return result == true
end

function PlayerDataServiceServer.savePlayerDataPromise(self: PlayerDataServiceServer, player: Player)
	return Promise.try(function()
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
			warn(("[PlayerDataService] Failed to save profile for %s (%d): %s"):format(
				player.Name,
				player.UserId,
				tostring(resultOrError)
			))
			return false
		end

		return true
	end)
end

function PlayerDataServiceServer.saveAllPlayerData(self: PlayerDataServiceServer)
	for player in self.playerRuntimes do
		self:savePlayerData(player)
	end
end

function PlayerDataServiceServer.destroy(self: PlayerDataServiceServer)
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
			runtime.loadPromise:cancel()
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

type PlayerDataServiceServer = typeof(PlayerDataServiceServer) & {
	networker: Networker.Server,
	profileStore: ProfileStoreObject,
	dataTemplate: PlayerData,
	playerRuntimes: { [Player]: PlayerRuntime },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return PlayerDataServiceServer :: PlayerDataServiceServer
