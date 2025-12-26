local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RaycastHitbox = require(ReplicatedStorage.Packages.RaycastHitbox)

local hitbox = RaycastHitbox.new

local Sword = {}
Sword.__index = Sword

export type Sword = typeof(setmetatable(
    {} :: {
        name: string?,
        damage: number,
        speed: number,
    }, Sword
))

function Sword.new()
    local self = setmetatable({
        conn = {},
    }, Sword)

    return self
end

function Sword:checkEquip()

end

function Sword:getTool()

end

function Sword:canSwing()

end

function Sword:swing()

end

function Sword:flourish()

end

function Sword:parry()

end

function Sword:gloryKill()

end

function Sword:block()

end

function Sword:destroy()
    for _, connection in pairs(self.conn) do
        connection:Disconnect()
    end
    self.conn = {}
end

return Sword