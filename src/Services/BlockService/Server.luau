local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networker = require(ReplicatedStorage.Packages.Networker)

local BlockServiceServer = {}

type BlockServiceServer = typeof(BlockServiceServer)

function BlockServiceServer.init(self: BlockServiceServer)
    local part = Instance.new("Part")
    
    self.part = part
    self.part.Name = "Block"

    self.networker = Networker.server.new("placeBlock", self, {
        self.test
    })
end

function BlockServiceServer.test(self: BlockServiceServer)
    print(self.part.Name)
end

return BlockServiceServer :: BlockServiceServer