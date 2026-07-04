local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local Maid = require("Maid")
local PlayerServiceServer = require("PlayerServiceServer")
local Rx: any = require("Rx")
local Table = require("Table")
local ValueObject = require("ValueObject")

local PlayerServer = {}
PlayerServer.ServiceName = "PlayerServer"

local maid = Maid.new()
local state = ValueObject.new({
	playerCount = 0,
	updatedAt = os.clock(),
})
local initialized = false

local function refreshState()
	state.Value = {
		playerCount = #Players:GetPlayers(),
		updatedAt = os.clock(),
	}
end

function PlayerServer.Init(_self: any)
	if initialized then
		return
	end

	initialized = true
	refreshState()
	maid:GiveTask(Rx.merge({
		Rx.fromSignal(Players.PlayerAdded),
		Rx.fromSignal(Players.PlayerRemoving),
	}):Subscribe(function()
		refreshState()
	end))
end

function PlayerServer.ObserveState(_self: any): any
	return state:Observe()
end

function PlayerServer.GetState(_self: any, player: Player): any
	if typeof((PlayerServiceServer :: any).GetState) ~= "function" then
		return nil
	end

	return (PlayerServiceServer :: any):GetState(player)
end

function PlayerServer.GetMovementService(_self: any): any
	return PlayerServiceServer
end

function PlayerServer.IsGameplayActiveForPlayer(_self: any, player: Player): boolean
	if typeof((PlayerServiceServer :: any).IsGameplayActiveForPlayer) ~= "function" then
		return false
	end

	return (PlayerServiceServer :: any):IsGameplayActiveForPlayer(player)
end

function PlayerServer.Destroy(_self: any)
	maid:DoCleaning()
	maid = Maid.new()
	initialized = false
	refreshState()
end

return Table.readonly(PlayerServer)
