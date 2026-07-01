local require = require(script.Parent.loader).load(script)

local Binder = require("Binder")
local BinderProvider = require("BinderProvider")
local AudioBinder = require("AudioBinder")
local ChunkBinder = require("ChunkBinder")
local DisturberBinder = require("DisturberBinder")
local FoliageBinder = require("FoliageBinder")
local LayerBinder = require("LayerBinder")
local LightBinder = require("LightBinder")
local LiquidBinder = require("LiquidBinder")
local PreviewBinder = require("PreviewBinder")
local TagBinder = require("TagBinder")
local TileBinder = require("TileBinder")
local UseBinder = require("UseBinder")

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

local BinderSupportClient = BinderProvider.new("BinderSupportClient", function(self)
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

return BinderSupportClient
