--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Signal = require(ReplicatedStorage.Packages.Signal)
local Sift = require(ReplicatedStorage.Packages.Sift)
local Ripple = require(ReplicatedStorage.Packages.Ripple)
local Promise = require(ReplicatedStorage.Packages.Promise)

local Npcs = ReplicatedStorage.Assets.Npcs

local npc = {}
npc.__index = npc

export type npc = typeof(setmetatable(
	{} :: {
		maxHp: number,
		dmg: number,
		def: number,
		model: Model,
		uniqueId: string,
	},
	npc
))

function npc.new(hp: number, dmg: number, def: number, model: Instance?)
	local self = {
		hp = hp,
		dmg = dmg,
		def = def,
		npcs = {},
		model = model,
		uniqueId = HttpService:GenerateGUID(),
	}

	setmetatable(self, npc)
	return self
end

function npc.start(self: npc)
	local npc = self.model:Clone()

	npc.Parent = workspace
	print("npc " .. self.uniqueId .. " was spawned")
end

function npc.takeDamage(self: npc) end

function npc.die(self: npc) end

function npc.giveDamage(self: npc) end

function npc.attack(self: npc) end

function npc.jump(self: npc) end

return npc
