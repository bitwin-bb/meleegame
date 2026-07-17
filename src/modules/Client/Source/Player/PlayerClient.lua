local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local Maid = require("Maid")
local PlayerMain = require("PlayerMain")
local RxPlayerUtils = require("RxPlayerUtils")
local ServiceBag = require("ServiceBag")
local Table = require("Table")

local PlayerClient = {}
PlayerClient.ServiceName = "PlayerClient"

local runtime = nil
local maid = Maid.new()
local runtimeMaid = Maid.new()
local runtimes = {}
local initialized = false

maid:GiveTask(runtimeMaid)

local function getPlayerRuntime(player: Player): any
	local playerRuntime = runtimes[player]
	if playerRuntime ~= nil then
		return playerRuntime
	end

	playerRuntime = PlayerMain.new(player, Players.LocalPlayer)
	runtimes[player] = playerRuntime
	runtimeMaid[player] = playerRuntime

	if player == Players.LocalPlayer then
		runtime = playerRuntime
	end

	return playerRuntime
end

local function getRuntime(): any
	if runtime == nil then
		runtime = getPlayerRuntime(Players.LocalPlayer)
	end
	return runtime
end

function PlayerClient.Init(_self: any, _serviceBag: ServiceBag.ServiceBag?)
	if initialized then
		return
	end

	initialized = true
	maid:GiveTask(RxPlayerUtils.observePlayersBrio():Subscribe(function(brio: any)
		if brio:IsDead() then
			return
		end

		local playerMaid, player = brio:ToMaidAndValue()
		local playerRuntime = getPlayerRuntime(player)
		playerRuntime:Start()

		playerMaid:GiveTask(function()
			if runtimes[player] ~= playerRuntime then
				return
			end

			runtimeMaid[player] = nil
			runtimes[player] = nil
			if runtime == playerRuntime then
				runtime = nil
			end
		end)
	end))
end

function PlayerClient.ObserveState(_self: any): any
	return getRuntime():ObserveState()
end

function PlayerClient.Destroy(_self: any)
	maid:DoCleaning()
	maid = Maid.new()
	runtimeMaid = Maid.new()
	maid:GiveTask(runtimeMaid)
	runtimes = {}
	runtime = nil
	initialized = false
end

return Table.readonly(PlayerClient)
