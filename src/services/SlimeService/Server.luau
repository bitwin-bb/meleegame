local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local npc = require(ReplicatedStorage.Shared.Classes.Npc)

local GreenSlime = ReplicatedStorage.Assets.Npcs.GreenSlime

local SlimeService = {}

function SlimeService.init(self: SlimeService)
	self.networker = Networker.server.new("SlimeService", self, {
		self.spawnEntity,
	})
end

function SlimeService.spawnEntity(self: SlimeService)
	local slime = npc.new(20, 20, 20, GreenSlime)
	slime:start()
end

type SlimeService = typeof(SlimeService) & {
	networker: Networker.Server,
	name: string,
}

return SlimeService :: SlimeService
