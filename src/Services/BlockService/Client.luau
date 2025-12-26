local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networker = require(ReplicatedStorage.Packages.Networker)

local BlockServiceClient = {}

type BlockServiceClient = typeof(BlockServiceClient)

function BlockServiceClient.init(self: BlockServiceClient)
    local newRemote = Networker.client.new("placeBlock", self :: BlockServiceClient)
    newRemote:fire("test")
end

return BlockServiceClient :: BlockServiceClient