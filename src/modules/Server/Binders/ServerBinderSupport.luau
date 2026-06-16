local require = require(script.Parent.loader).load(script)

local Binder = require("Binder")
local BinderProvider = require("BinderProvider")
local BossBinder = require("BossBinder")
local BreakableBinder = require("BreakableBinder")
local BreathBinder = require("BreathBinder")
local CharacterBinder = require("CharacterBinder")
local DropBinder = require("DropBinder")
local GoreBinder = require("GoreBinder")
local HazardBinder = require("HazardBinder")
local HitboxBinder = require("HitboxBinder")
local LootBinder = require("LootBinder")
local MagicBinder = require("MagicBinder")
local MeleeBinder = require("MeleeBinder")
local NpcBinder = require("NpcBinder")
local PickupBinder = require("PickupBinder")
local PlaceableBinder = require("PlaceableBinder")
local RagdollBinder = require("RagdollBinder")
local ServerChunkBinder = require("ServerChunkBinder")
local StationBinder = require("StationBinder")
local TagBinder = require("TagBinder")
local UnitBinder = require("UnitBinder")

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

local ServerBinderSupport = BinderProvider.new("ServerBinderSupport", function(self)
	addBinder(self, TagBinder.Tags.Boss, BossBinder)
	addBinder(self, TagBinder.Tags.Breakable, BreakableBinder)
	addBinder(self, TagBinder.Tags.Breath, BreathBinder)
	addBinder(self, TagBinder.Tags.Character, CharacterBinder)
	addBinder(self, TagBinder.Tags.Chunk, ServerChunkBinder)
	addBinder(self, TagBinder.Tags.Drop, DropBinder)
	addBinder(self, TagBinder.Tags.Gore, GoreBinder)
	addBinder(self, TagBinder.Tags.Hazard, HazardBinder)
	addBinder(self, TagBinder.Tags.Hitbox, HitboxBinder)
	addBinder(self, TagBinder.Tags.Loot, LootBinder)
	addBinder(self, TagBinder.Tags.Magic, MagicBinder)
	addBinder(self, TagBinder.Tags.Melee, MeleeBinder)
	addBinder(self, TagBinder.Tags.Npc, NpcBinder)
	addBinder(self, TagBinder.Tags.Pickup, PickupBinder)
	addBinder(self, TagBinder.Tags.Placeable, PlaceableBinder)
	addBinder(self, TagBinder.Tags.Ragdoll, RagdollBinder)
	addBinder(self, TagBinder.Tags.Station, StationBinder)
	addBinder(self, TagBinder.Tags.Unit, UnitBinder)
end)

return ServerBinderSupport
