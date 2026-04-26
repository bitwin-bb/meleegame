--!strict

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(script)

local Binder = loader("Binder")
local BinderProvider = loader("BinderProvider")
local BossBinder = require(script.Parent.BossBinder)
local BreakableBinder = require(script.Parent.BreakableBinder)
local BreathBinder = require(script.Parent.BreathBinder)
local CharacterBinder = require(script.Parent.CharacterBinder)
local DropBinder = require(script.Parent.DropBinder)
local GoreBinder = require(script.Parent.GoreBinder)
local HazardBinder = require(script.Parent.HazardBinder)
local HitboxBinder = require(script.Parent.HitboxBinder)
local LootBinder = require(script.Parent.LootBinder)
local MagicBinder = require(script.Parent.MagicBinder)
local MeleeBinder = require(script.Parent.MeleeBinder)
local NpcBinder = require(script.Parent.NpcBinder)
local PickupBinder = require(script.Parent.PickupBinder)
local PlaceableBinder = require(script.Parent.PlaceableBinder)
local RagdollBinder = require(script.Parent.RagdollBinder)
local ServerChunkBinder = require(script.Parent.ServerChunkBinder)
local StationBinder = require(script.Parent.StationBinder)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)
local UnitBinder = require(script.Parent.UnitBinder)

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
