--!strict

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local Binder = loader("Binder")
local BinderProvider = loader("BinderProvider")
local BossBinder = require(script:FindFirstAncestor("game").Shared.Features.npc.binders.BossBinder)
local BreakableBinder = require(script:FindFirstAncestor("game").Shared.Features.world.binders.BreakableBinder)
local BreathBinder = require(script:FindFirstAncestor("game").Shared.Features.breath.binders.BreathBinder)
local CharacterBinder = require(script:FindFirstAncestor("game").Shared.Features.movement.binders.CharacterBinder)
local DropBinder = (require :: any)(script:FindFirstAncestor("game").Shared.Features.loot.binders.DropBinder)
local GoreBinder = (require :: any)(script:FindFirstAncestor("game").Shared.Features.gore.binders.GoreBinder)
local HazardBinder = (require :: any)(script:FindFirstAncestor("game").Shared.Features.combat.binders.HazardBinder)
local HitboxBinder = (require :: any)(script:FindFirstAncestor("game").Shared.Features.combat.binders.HitboxBinder)
local LootBinder = require(script:FindFirstAncestor("game").Shared.Features.loot.binders.LootBinder)
local MagicBinder = (require :: any)(script:FindFirstAncestor("game").Shared.Features.combat.binders.MagicBinder)
local MeleeBinder = (require :: any)(script:FindFirstAncestor("game").Shared.Features.combat.binders.MeleeBinder)
local NpcBinder = require(script:FindFirstAncestor("game").Shared.Features.npc.binders.NpcBinder)
local PickupBinder = (require :: any)(script:FindFirstAncestor("game").Shared.Features.loot.binders.PickupBinder)
local PlaceableBinder = require(script:FindFirstAncestor("game").Shared.Features.world.binders.PlaceableBinder)
local RagdollBinder = require(script:FindFirstAncestor("game").Shared.Features.ragdoll.binders.RagdollBinder)
local ServerChunkBinder =
	require(script:FindFirstAncestor("game").Shared.Features.worldGeneration.binders.ServerChunkBinder)
local StationBinder = require(script:FindFirstAncestor("game").Shared.Features.crafting.binders.StationBinder)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)
local UnitBinder = require(script:FindFirstAncestor("game").Shared.Features.combat.binders.UnitBinder)

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
