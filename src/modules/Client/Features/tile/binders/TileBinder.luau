--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")

local Maid = require(quentyPackages.maid.Shared.Maid)
local Rx = require(quentyPackages.rx.Shared.Rx)

local Shiny = require(gameRoot.Client.Features.tile.classes.Shiny)

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> number,
	Destroy: (self: MaidClass) -> (),
	[any]: any,
}

local TileBinder = {}
TileBinder.__index = TileBinder

TileBinder.TAG_NAME = "Tile"

export type TileBinder = typeof(setmetatable(
	{} :: {
		instance: Instance,
		context: any?,
		maid: MaidClass,
		shiny: any?,
		destroyed: boolean,
	},
	TileBinder
))

local function createMaid(): MaidClass
	return Maid.new() :: MaidClass
end

function TileBinder.new(instanceRaw: any, contextRaw: any?): TileBinder
	if typeof(instanceRaw) ~= "Instance" then
		error("TileBinder.new expects an Instance")
	end

	local self = setmetatable({
		instance = instanceRaw :: Instance,
		context = if typeof(contextRaw) == "table" then contextRaw else nil,
		maid = createMaid(),
		shiny = nil :: any?,
		destroyed = false,
	}, TileBinder)

	self.maid:GiveTask(self.instance.Destroying:Connect(function()
		self:Destroy()
	end))

	self:bindTileState()
	return self
end

function TileBinder.BindTileState(self: TileBinder)
	self.maid:GiveTask(Rx.merge({
		Rx.fromSignal(self.instance:GetAttributeChangedSignal("TileId")),
		Rx.fromSignal(self.instance:GetAttributeChangedSignal("TileIsOre")),
		Rx.fromSignal(self.instance:GetAttributeChangedSignal("TileName")),
	})
		:Pipe({
			Rx.start(function()
				return nil
			end),
		})
		:Subscribe(function()
			self:refresh()
		end))
end

function TileBinder.Refresh(self: TileBinder)
	if self.destroyed then
		return
	end

	if not self.instance:IsA("BasePart") then
		self.maid._shiny = nil
		self.shiny = nil
		return
	end

	if not Shiny.isOreTile(self.instance) then
		self.maid._shiny = nil
		self.shiny = nil
		return
	end

	if self.shiny ~= nil then
		return
	end

	local shiny = Shiny.new(self.instance, self.context)
	self.shiny = shiny
	self.maid._shiny = shiny
end

function TileBinder.Destroy(self: TileBinder)
	if self.destroyed then
		return
	end

	self.destroyed = true
	self.maid:Destroy()
end

TileBinder.bindTileState = TileBinder.BindTileState
TileBinder.refresh = TileBinder.Refresh
TileBinder.destroy = TileBinder.Destroy

return TileBinder
