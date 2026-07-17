local require = require(script.Parent.loader).load(script)

local AudioBinder = require("AudioBinder")
local Binder = require("Binder")
local BinderProvider = require("BinderProvider")
local DisturberBinder = require("DisturberBinder")
local FoliageBinder = require("FoliageBinder")
local LayerBinder = require("LayerBinder")
local LightBinder = require("LightBinder")
local LiquidBinder = require("LiquidBinder")
local ModelBinder = require("ModelBinder")
local PreviewBinder = require("PreviewBinder")
local ServiceBag = require("ServiceBag")
local Table = require("Table")
local TagBinder = require("TagBinder")
local TileBinder = require("TileBinder")
local TileChunkClient = require("TileChunkClient")
local UseBinder = require("UseBinder")

local function createContext(
	primaryTag: string,
	serviceBag: ServiceBag.ServiceBag,
	dependencies: ModelBinder.BinderDependencies
): ModelBinder.BinderContext
	return table.freeze({
		dependencies = dependencies,
		serviceBag = serviceBag,
		tags = table.freeze({ primaryTag }),
	})
end

local function addBinder(
	self: any,
	primaryTag: string,
	binderClass: any,
	serviceBag: ServiceBag.ServiceBag,
	dependencies: ModelBinder.BinderDependencies
)
	self:Add(Binder.new(primaryTag, function(instance: Instance)
		return binderClass.new(instance, createContext(primaryTag, serviceBag, dependencies))
	end, serviceBag))
end

local function addAutotileChunkBinder(
	self: any,
	serviceBag: ServiceBag.ServiceBag,
	dependencies: ModelBinder.BinderDependencies
)
	self:Add(Binder.new(TagBinder.Tags.Chunk, function(instance: Instance)
		local renderService =
			assert(dependencies.AutotileRenderServiceClient, "AutotileRenderServiceClient dependency is unavailable")
		return TileChunkClient.new(
			instance,
			table.freeze({
				dependencies = dependencies,
				serviceBag = serviceBag,
				tags = table.freeze({ TagBinder.Tags.Chunk }),
				renderService = renderService,
				wallRenderService = dependencies.WallAutotileServiceClient,
			})
		)
	end, serviceBag))
end

local BinderSupportClient = BinderProvider.new("BinderSupportClient", function(self, serviceBag: ServiceBag.ServiceBag)
	local dependencies = {} :: ModelBinder.BinderDependencies
	self._dependencies = dependencies

	addBinder(self, TagBinder.Tags.Audio, AudioBinder, serviceBag, dependencies)
	addAutotileChunkBinder(self, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Disturber, DisturberBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Foliage, FoliageBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Layer, LayerBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Light_Torch, LightBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Liquid, LiquidBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Preview, PreviewBinder, serviceBag, dependencies)
	addBinder(self, TileBinder.TAG_NAME, TileBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Use, UseBinder, serviceBag, dependencies)
end)

function BinderSupportClient.ConfigureDependencies(self: any, dependencies: ModelBinder.BinderDependencies)
	assert(self._initialized, "BinderSupportClient is not initialized")
	assert(not self._started, "BinderSupportClient already started")
	Table.overwrite(self._dependencies, dependencies)
end

return BinderSupportClient
