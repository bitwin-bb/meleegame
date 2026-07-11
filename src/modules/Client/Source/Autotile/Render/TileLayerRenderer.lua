local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion: any = require(ReplicatedStorage.Packages.Fusion)
local Maid = require("Maid")

local BuildServiceUtils = require("BuildServiceUtils")
local TileSprite = require("TileSprite")

local TileLayerRenderer = {}
TileLayerRenderer.__index = TileLayerRenderer

function TileLayerRenderer.new(parent: Instance): any
	local scope = Fusion.scoped(Fusion)
	local maid = Maid.new()

	local self = setmetatable({
		_maid = maid,
		_scope = scope,
		_spritesByKey = {},
		_container = scope:New "Folder" {
			Name = "AutotileLayer",
			Parent = parent,
		},
	}, TileLayerRenderer)

	maid:GiveTask(function()
		Fusion.doCleanup(scope)
	end)

	return self
end

function TileLayerRenderer.GetSprite(self: any, localX: number, localY: number): any?
	return self._spritesByKey[BuildServiceUtils.PackTileKey(localX, localY)]
end

function TileLayerRenderer.SetTile(self: any, localX: number, localY: number, atlasResult: any?, layout: any?)
	if atlasResult == nil then
		self:ClearTile(localX, localY)
		return
	end

	local key = BuildServiceUtils.PackTileKey(localX, localY)
	local sprite = self._spritesByKey[key]
	if sprite == nil then
		sprite = TileSprite.new(self._container, localX, localY, layout)
		self._spritesByKey[key] = sprite
	else
		sprite:SetLayout(localX, localY, layout)
	end

	sprite:Update(atlasResult)
end

function TileLayerRenderer.ClearTile(self: any, localX: number, localY: number)
	local key = BuildServiceUtils.PackTileKey(localX, localY)
	local sprite = self._spritesByKey[key]
	if sprite == nil then
		return
	end

	self._spritesByKey[key] = nil
	sprite:Destroy()
end

function TileLayerRenderer.Clear(self: any)
	for key, sprite in self._spritesByKey do
		self._spritesByKey[key] = nil
		sprite:Destroy()
	end
end

function TileLayerRenderer.Destroy(self: any)
	self:Clear()
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	self._scope = nil
	self._container = nil
end

return TileLayerRenderer
