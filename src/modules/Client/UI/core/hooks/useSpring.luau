local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Spring = require(script:FindFirstAncestor("game").Shared.Modules.Math.Spring)

local e = React.createElement :: typeof(React.createElement)

export type Spring = {
    spring: Spring,
}

local function useSpring() end

return useSpring