--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local ProfileStore = require(ReplicatedStorage.Packages.ProfileStore)
local PlayerDataServiceUtils = require(ReplicatedStorage.Shared.Services.PlayerDataService.PlayerDataServiceUtils)
local DataTemplate = require(ReplicatedStorage.Shared.Modules.Core.DataTemplate)

type PlayerData = PlayerDataServiceUtils.PlayerData
type LoadState = PlayerDataServiceUtils.LoadState
type Profile = ProfileStore.Profile<PlayerData>
type ProfileStoreObject = ProfileStore.ProfileStore<PlayerData>
type ProfileSignalConnection = {
	Disconnect: (self: ProfileSignalConnection) -> (),
}

type PlayerRuntime = {
	loadToken: number,
	loadState: LoadState,
	profile: Profile?,
	data: PlayerData?,
	profileEndedConnection: ProfileSignalConnection?,
}

local PlayerDataServiceServer = {}

local DATA_LOAD_FAILED_KICK_MESSAGE = "Unable to load your data. Please rejoin."
local DATA_SESSION_ENDED_KICK_MESSAGE = "Your data session ended. Please rejoin."

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

function PlayerDataServiceServer.pushState(self: PlayerDataServiceServer, player: Player)
	if self.networker == nil then
		return
	end

	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		self.networker:fire(player, "applyState", nil, PlayerDataServiceUtils.LOAD_STATE_UNLOADED)
		return
	end

	local dataSnapshot = if runtime.data ~= nil then PlayerDataServiceUtils.cloneDeep(runtime.data) else nil
	self.networker:fire(player, "applyState", dataSnapshot, runtime.loadState)
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

function PlayerDataServiceServer.loadProfileAsync(
	self: PlayerDataServiceServer,
	player: Player,
	loadToken: number
)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end
	if runtime.loadToken ~= loadToken then
		return
	end

	local profileKey = PlayerDataServiceUtils.getProfileKey(player)
	if profileKey == nil then
		runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_FAILED
		self:pushState(player)
		if player.Parent == Players and not ProfileStore.IsClosing then
			player:Kick(DATA_LOAD_FAILED_KICK_MESSAGE)
		end
		return
	end

	local profile: Profile? = nil
	local success, resultOrError = pcall(function()
		return self.profileStore:StartSessionAsync(profileKey, {
			Cancel = function()
				local currentRuntime = self.playerRuntimes[player]
				if currentRuntime == nil then
					return true
				end
				return currentRuntime.loadToken ~= loadToken
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
		return
	end

	if profile == nil then
		runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_FAILED
		self:pushState(player)
		if player.Parent == Players and not ProfileStore.IsClosing then
			player:Kick(DATA_LOAD_FAILED_KICK_MESSAGE)
		end
		return
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
end

function PlayerDataServiceServer.trackPlayer(self: PlayerDataServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	runtime.loadToken += 1
	self:releaseProfile(runtime)
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_LOADING
	self:pushState(player)

	local currentLoadToken = runtime.loadToken
	task.spawn(function()
		self:loadProfileAsync(player, currentLoadToken)
	end)
end

function PlayerDataServiceServer.untrackPlayer(self: PlayerDataServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	self.playerRuntimes[player] = nil
	runtime.loadToken += 1
	runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_UNLOADED
	self:releaseProfile(runtime)
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
	local timeoutSeconds = if typeof(timeoutSecondsRaw) == "number" and timeoutSecondsRaw == timeoutSecondsRaw
		then math.max(0, timeoutSecondsRaw)
		else 15
	local startedAt = os.clock()

	while true do
		local runtime = self:getActiveRuntime(player)
		if runtime and runtime.data ~= nil then
			return runtime.data
		end

		local trackedRuntime = self.playerRuntimes[player]
		if trackedRuntime == nil then
			return nil
		end
		if trackedRuntime.loadState == PlayerDataServiceUtils.LOAD_STATE_FAILED then
			return nil
		end
		if os.clock() - startedAt >= timeoutSeconds then
			return nil
		end

		task.wait()
	end
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
		runtime.loadState = PlayerDataServiceUtils.LOAD_STATE_UNLOADED
		self:releaseProfile(runtime)
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
