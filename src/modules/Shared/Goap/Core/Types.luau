--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

export type FactTable = { [string]: any }
export type WorldStateLike = FactTable | any
export type ActionLike = any
export type GoalLike = any
export type SensorLike = any
export type PlanLike = any
export type AgentLike = any

return Table.copy({})
