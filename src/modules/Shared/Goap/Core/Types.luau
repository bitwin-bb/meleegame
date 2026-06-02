--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

export type FactTable = { [string]: any }
export type WorldStateLike = FactTable | any
export type ActionLike = any
export type GoalLike = any
export type SensorLike = any
export type PlanLike = any
export type AgentLike = any

return Table.copy({})
