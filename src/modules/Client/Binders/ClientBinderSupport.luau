--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")

local Binder = require(quentyPackages.binder.Shared.Binder)
local BinderProvider = require(quentyPackages.binder.Shared.BinderProvider)
local AudioBinder = (require :: any)(gameRoot.Client.Features.audio.binders.AudioBinder)
local ChunkBinder = (require :: any)(gameRoot.Shared.Features.worldGeneration.binders.ChunkBinder)
local DisturberBinder = (require :: any)(gameRoot.Shared.Features.world.binders.DisturberBinder)
local FoliageBinder = (require :: any)(gameRoot.Shared.Features.world.binders.FoliageBinder)
local LayerBinder = require(gameRoot.Shared.Features.world.binders.LayerBinder)
local LightBinder = require(gameRoot.Shared.Features.world.binders.LightBinder)
local LiquidBinder = require(gameRoot.Shared.Features.world.binders.LiquidBinder)
local PreviewBinder = (require :: any)(gameRoot.Shared.Features.world.binders.PreviewBinder)
local TagBinder = require(gameRoot.Shared.Binders.TagBinder)
local TileBinder = require(gameRoot.Client.Features.tile.binders.TileBinder)
local UseBinder = require(gameRoot.Client.Features.interaction.binders.UseBinder)

local function createContext(primaryTag: string, serviceBag: any): { tags: { string }, serviceBag: any }
	return table.freeze({
		serviceBag = serviceBag,
		tags = table.freeze({ primaryTag }),
	})
end

local function addBinder(self: any, primaryTag: string, binderClass: any)
	self:Add(Binder.new(primaryTag, function(instance: Instance, serviceBag: any)
		return binderClass.new(instance, createContext(primaryTag, serviceBag))
	end))
end

local ClientBinderSupport = BinderProvider.new("ClientBinderSupport", function(self)
	addBinder(self, TagBinder.Tags.Audio, AudioBinder)
	addBinder(self, TagBinder.Tags.Chunk, ChunkBinder)
	addBinder(self, TagBinder.Tags.Disturber, DisturberBinder)
	addBinder(self, TagBinder.Tags.Foliage, FoliageBinder)
	addBinder(self, TagBinder.Tags.Layer, LayerBinder)
	addBinder(self, TagBinder.Tags.Light_Torch, LightBinder)
	addBinder(self, TagBinder.Tags.Liquid, LiquidBinder)
	addBinder(self, TagBinder.Tags.Preview, PreviewBinder)
	addBinder(self, TileBinder.TAG_NAME, TileBinder)
	addBinder(self, TagBinder.Tags.Use, UseBinder)
end)

return ClientBinderSupport
