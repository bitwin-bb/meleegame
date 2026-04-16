--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.ConnectionUtils)
local deathSlice = require(script:FindFirstAncestor("game").Client.UI.features.death.state.deathSlice)
local PlayerSpawnCooldown = require(script:FindFirstAncestor("game").Shared.Modules.Game.Player.PlayerSpawnCooldown)

type DeathState = deathSlice.DeathState

local deathThunks = {}

local runtime = {
	started = false,
	localPlayer = nil :: Player?,
	boundCharacter = nil :: Model?,
	boundHumanoid = nil :: Humanoid?,
	deathShownForHumanoid = nil :: Humanoid?,
	characterAddedConnection = nil :: RBXScriptConnection?,
	characterChildAddedConnection = nil :: RBXScriptConnection?,
	characterChildRemovedConnection = nil :: RBXScriptConnection?,
	humanoidDiedConnection = nil :: RBXScriptConnection?,
}

local function resolveRespawnDelay(): number
	return PlayerSpawnCooldown.getCurrentRespawnDelay()
end

local function isHumanoidDead(humanoidRaw: any): boolean
	if typeof(humanoidRaw) ~= "Instance" or not humanoidRaw:IsA("Humanoid") then
		return false
	end
	local humanoid = humanoidRaw :: Humanoid
	return humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead
end

local function unbindHumanoid()
	ConnectionUtils.disconnect(runtime.humanoidDiedConnection)
	runtime.humanoidDiedConnection = nil
	runtime.boundHumanoid = nil
end

local function onHumanoidDied(humanoid: Humanoid)
	if runtime.boundHumanoid ~= humanoid then
		return
	end
	if runtime.deathShownForHumanoid == humanoid then
		return
	end

	runtime.deathShownForHumanoid = humanoid
	deathSlice.showDeath({
		message = "You were slain...",
		respawnDelay = resolveRespawnDelay(),
	})
end

local function bindHumanoid(humanoid: Humanoid)
	if runtime.boundHumanoid == humanoid then
		return
	end

	unbindHumanoid()
	runtime.boundHumanoid = humanoid
	runtime.humanoidDiedConnection = humanoid.Died:Connect(function()
		onHumanoidDied(humanoid)
	end)

	if isHumanoidDead(humanoid) then
		onHumanoidDied(humanoid)
	end
end

local function bindCharacter(characterRaw: any)
	if typeof(characterRaw) ~= "Instance" or not characterRaw:IsA("Model") then
		return
	end
	local character = characterRaw :: Model
	runtime.boundCharacter = character
	runtime.deathShownForHumanoid = nil
	local deathState = deathSlice.getDeathState()
	if deathState.visible then
		deathSlice.setDeathState({
			visible = true,
			message = deathState.message,
			diedAt = deathState.diedAt,
			respawnDelay = deathState.respawnDelay,
			respawnAt = os.clock(),
			sequence = deathState.sequence,
		})
	end

	ConnectionUtils.disconnect(runtime.characterChildAddedConnection)
	ConnectionUtils.disconnect(runtime.characterChildRemovedConnection)
	runtime.characterChildAddedConnection = character.ChildAdded:Connect(function(child: Instance)
		if runtime.boundCharacter ~= character then
			return
		end
		if child:IsA("Humanoid") then
			bindHumanoid(child)
		end
	end)
	runtime.characterChildRemovedConnection = character.ChildRemoved:Connect(function(child: Instance)
		if runtime.boundCharacter ~= character then
			return
		end
		if child == runtime.boundHumanoid then
			unbindHumanoid()
		end
	end)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		bindHumanoid(humanoid)
	else
		unbindHumanoid()
	end
end

function deathThunks.Start(): () -> ()
	if runtime.started then
		return deathThunks.Stop
	end

	runtime.started = true
	runtime.localPlayer = Players.LocalPlayer
	local localPlayer = runtime.localPlayer
	if localPlayer == nil then
		return deathThunks.Stop
	end

	runtime.characterAddedConnection = localPlayer.CharacterAdded:Connect(function(character: Model)
		if not runtime.started then
			return
		end
		bindCharacter(character)
	end)

	if localPlayer.Character ~= nil then
		bindCharacter(localPlayer.Character)
	end

	return deathThunks.Stop
end

function deathThunks.Stop()
	ConnectionUtils.disconnectMany({
		runtime.characterAddedConnection,
		runtime.characterChildAddedConnection,
		runtime.characterChildRemovedConnection,
		runtime.humanoidDiedConnection,
	})
	runtime.characterAddedConnection = nil
	runtime.characterChildAddedConnection = nil
	runtime.characterChildRemovedConnection = nil
	runtime.humanoidDiedConnection = nil

	runtime.started = false
	runtime.localPlayer = nil
	runtime.boundCharacter = nil
	runtime.boundHumanoid = nil
	runtime.deathShownForHumanoid = nil
	deathSlice.resetDeathState()
end

function deathThunks.GetDeathState(): DeathState
	return deathSlice.getDeathState()
end

deathThunks.start = deathThunks.Start
deathThunks.stop = deathThunks.Stop
deathThunks.getDeathState = deathThunks.GetDeathState

return deathThunks
