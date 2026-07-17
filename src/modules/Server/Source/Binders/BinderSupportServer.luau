local require = require(script.Parent.loader).load(script)

local Binder = require("Binder")
local BinderProvider = require("BinderProvider")
local BossBinder = require("BossBinder")
local BreakableBinder = require("BreakableBinder")
local BreathBinder = require("BreathBinder")
local CharacterBinder = require("CharacterBinder")
local ChunkBinderServer = require("ChunkBinderServer")
local DropBinder = require("DropBinder")
local GoreBinder = require("GoreBinder")
local HazardBinder = require("HazardBinder")
local HitboxBinder = require("HitboxBinder")
local LootBinder = require("LootBinder")
local MagicBinder = require("MagicBinder")
local MeleeBinder = require("MeleeBinder")
local ModelBinder = require("ModelBinder")
local NpcBinder = require("NpcBinder")
local PickupBinder = require("PickupBinder")
local PlaceableBinder = require("PlaceableBinder")
local RagdollBinder = require("RagdollBinder")
local ServiceBag = require("ServiceBag")
local StationBinder = require("StationBinder")
local Table = require("Table")
local TagBinder = require("TagBinder")
local UnitBinder = require("UnitBinder")

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

local BinderSupportServer = BinderProvider.new("BinderSupportServer", function(self, serviceBag: ServiceBag.ServiceBag)
	local dependencies = {} :: ModelBinder.BinderDependencies
	self._dependencies = dependencies

	addBinder(self, TagBinder.Tags.Boss, BossBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Breakable, BreakableBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Breath, BreathBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Character, CharacterBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Chunk, ChunkBinderServer, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Drop, DropBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Gore, GoreBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Hazard, HazardBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Hitbox, HitboxBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Loot, LootBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Magic, MagicBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Melee, MeleeBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Npc, NpcBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Pickup, PickupBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Placeable, PlaceableBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Ragdoll, RagdollBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Station, StationBinder, serviceBag, dependencies)
	addBinder(self, TagBinder.Tags.Unit, UnitBinder, serviceBag, dependencies)
end)

function BinderSupportServer.ConfigureDependencies(self: any, dependencies: ModelBinder.BinderDependencies)
	assert(self._initialized, "BinderSupportServer is not initialized")
	assert(not self._started, "BinderSupportServer already started")
	Table.overwrite(self._dependencies, dependencies)
end

return BinderSupportServer
