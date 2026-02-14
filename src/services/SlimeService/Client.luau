--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)

local SlimeServiceClient = {}

function SlimeServiceClient.init(self: SlimeServiceClient)
	self.networker = Networker.client.new("SlimeService", self)
	self:attemptSpawn()
end

function SlimeServiceClient.attemptSpawn(self: SlimeServiceClient)
	self.networker:fire("spawnEntity")
end

type SlimeServiceClient = typeof(SlimeServiceClient) & {
	networker: Networker.Client,
}

return SlimeServiceClient :: SlimeServiceClient
