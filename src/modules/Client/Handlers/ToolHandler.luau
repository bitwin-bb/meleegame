
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Maid = Nevermore.Get("Maid")
local Signal = Nevermore.Get("Signal")
local ToolUtils = Nevermore.Get("ToolUtils")

local ToolHandler = {}
ToolHandler.__index = ToolHandler

export type ToolHandler = typeof(setmetatable(
	{} :: {
		maid: any,
		EquippedChanged: any,
		tool: Tool?,
	},
	ToolHandler
))

function ToolHandler.new(toolRaw: any?): ToolHandler
	local self = setmetatable({
		maid = Maid.new(),
		EquippedChanged = Signal.new(),
		tool = nil,
	}, ToolHandler)

	self.maid:GiveTask(self.EquippedChanged)
	self:SetTool(toolRaw)
	return self
end

function ToolHandler.SetTool(self: ToolHandler, toolRaw: any?)
	local tool = if typeof(toolRaw) == "Instance" and toolRaw:IsA("Tool") then toolRaw else nil
	if self.tool == tool then
		return
	end
	self.tool = tool
	self.EquippedChanged:Fire(tool)
end

function ToolHandler.GetTool(self: ToolHandler): Tool?
	return self.tool
end

function ToolHandler.GetEquippedHumanoid(self: ToolHandler): Humanoid?
	return if self.tool ~= nil then ToolUtils.getEquippedHumanoid(self.tool) else nil
end

function ToolHandler.GetEquippedPlayer(self: ToolHandler): Player?
	return if self.tool ~= nil then ToolUtils.getEquippedPlayer(self.tool) else nil
end

function ToolHandler.Destroy(self: ToolHandler)
	self.maid:DoCleaning()
	self.tool = nil
end
return ToolHandler
