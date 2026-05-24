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

function MatterDebugMenuClient.ApplyEnabledState(self: MatterDebugMenuClient)
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

function MatterDebugMenuClient.Init(self: MatterDebugMenuClient)
	if self.initialized then
		return
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return
	end

	local world = (Matter.World.new :: any)()
	local loop = (Matter.Loop.new :: any)(world, self)
	local debugger = (Matter.Debugger.new :: any)(Plasma)
	debugger:autoInitialize(loop)
	local connection: ConnectionMap = loop:begin({
		default = RunService.Heartbeat,
	}) :: any
	local attributeConnection = localPlayer
		:GetAttributeChangedSignal(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE)
		:Connect(function()
			self:applyEnabledState()
		end)

	self.localPlayer = localPlayer
	self.world = world
	self.loop = loop
	self.debugger = debugger
	self.connection = connection
	self.attributeConnection = attributeConnection
	self.initialized = true
	self:applyEnabledState()
end

function MatterDebugMenuClient.Destroy(self: MatterDebugMenuClient)
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

