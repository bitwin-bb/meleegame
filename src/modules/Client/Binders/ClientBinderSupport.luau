--!strict

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local nevermoreRequire = require(loaderUtils.Parent).load(script)

local Binder = nevermoreRequire("Binder")
local BinderProvider = nevermoreRequire("BinderProvider")
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)
local AudioBinder = require(script.Parent.AudioBinder)
local ChunkBinder = require(script.Parent.ChunkBinder)
local DisturberBinder = require(script.Parent.DisturberBinder)
local FoliageBinder = require(script.Parent.FoliageBinder)
local LayerBinder = require(script.Parent.LayerBinder)
local LightBinder = require(script.Parent.LightBinder)
local LiquidBinder = require(script.Parent.LiquidBinder)
local PreviewBinder = require(script.Parent.PreviewBinder)
local UseBinder = require(script.Parent.UseBinder)

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
	addBinder(self, TagBinder.Tags.Use, UseBinder)
end)

return ClientBinderSupport
