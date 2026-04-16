--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Matter = require(ReplicatedStorage.Packages.Matter)
local Plasma = require(ReplicatedStorage.Packages.Plasma)

local CmdrUtils = require(script:FindFirstAncestor("game").Shared.Cmdr.CmdrUtils)

local MatterDebugMenuClient = {}

type ConnectionMap = {
	default: RBXScriptConnection,
}

type MatterDebugMenuClient = typeof(MatterDebugMenuClient) & {
	localPlayer: Player?,
	world: any,
	loop: any,
	debugger: any,
	connection: ConnectionMap?,
	attributeConnection: RBXScriptConnection?,
	initialized: boolean,
}

function MatterDebugMenuClient:ApplyEnabledState()
	local localPlayer = self.localPlayer
	local debugger = self.debugger
	if localPlayer == nil or debugger == nil then
		return
	end

	local enabled = localPlayer:GetAttribute(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE) == true
	if enabled then
		debugger:show()
		debugger:switchToServerView()
	else
		debugger:hide()
	end
end

function MatterDebugMenuClient:Init()
	if self.initialized then
		return
	end

	self.initialized = true
	self.localPlayer = Players.LocalPlayer
	self.world = Matter.World.new()
	self.loop = Matter.Loop.new(self.world, self)
	self.debugger = Matter.Debugger.new(Plasma)
	self.debugger:autoInitialize(self.loop)
	self.connection = self.loop:begin({
		default = RunService.Heartbeat,
	})
	self.attributeConnection = self.localPlayer:GetAttributeChangedSignal(
		CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE
	):Connect(function()
		self:applyEnabledState()
	end)

	self:applyEnabledState()
end

function MatterDebugMenuClient:Destroy()
	if self.attributeConnection ~= nil then
		self.attributeConnection:Disconnect()
		self.attributeConnection = nil
	end
	if self.connection ~= nil then
		self.connection.default:Disconnect()
		self.connection = nil
	end
	self.debugger = nil
	self.loop = nil
	self.world = nil
	self.localPlayer = nil
	self.initialized = false
end

MatterDebugMenuClient.applyEnabledState = MatterDebugMenuClient.ApplyEnabledState
MatterDebugMenuClient.init = MatterDebugMenuClient.Init
MatterDebugMenuClient.destroy = MatterDebugMenuClient.Destroy

return MatterDebugMenuClient :: MatterDebugMenuClient
