local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local Maid = require("Maid")
local PlayerMain = require("PlayerMain")
local Table = require("Table")

local PlayerClient = {}

local runtime = nil
local maid = Maid.new()

local function getRuntime(): any
	if runtime == nil then
		runtime = PlayerMain.new(Players.LocalPlayer)
		maid:GiveTask(runtime)
	end
	return runtime
end

function PlayerClient.Init(_self: any)
	getRuntime():Start()
end

function PlayerClient.ObserveState(_self: any): any
	return getRuntime():ObserveState()
end

function PlayerClient.Destroy(_self: any)
	maid:DoCleaning()
	maid = Maid.new()
	runtime = nil
end

return Table.readonly(PlayerClient)
