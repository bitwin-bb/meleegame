--!strict

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local Binder = loader("Binder")
local BinderProvider = loader("BinderProvider")
local AudioBinder = (require :: any)(script:FindFirstAncestor("game").Client.Features.audio.binders.AudioBinder)
local ChunkBinder = (require :: any)(script:FindFirstAncestor("game").Shared.Features.worldGeneration.binders.ChunkBinder)
local DisturberBinder = (require :: any)(script:FindFirstAncestor("game").Shared.Features.world.binders.DisturberBinder)
local FoliageBinder = (require :: any)(script:FindFirstAncestor("game").Shared.Features.world.binders.FoliageBinder)
local LayerBinder = require(script:FindFirstAncestor("game").Shared.Features.world.binders.LayerBinder)
local LightBinder = require(script:FindFirstAncestor("game").Shared.Features.world.binders.LightBinder)
local LiquidBinder = require(script:FindFirstAncestor("game").Shared.Features.world.binders.LiquidBinder)
local PreviewBinder = (require :: any)(script:FindFirstAncestor("game").Shared.Features.world.binders.PreviewBinder)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)
local TileBinder = require(script:FindFirstAncestor("game").Client.Features.tile.binders.TileBinder)
local UseBinder = require(script:FindFirstAncestor("game").Client.Features.interaction.binders.UseBinder)

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
