--!strict

local Utils = {}

Utils.Shared = require(script.Parent.Shared)
Utils.Config = require(script.Parent.SimulationConfig)
Utils.State = require(script.Parent.SimulationState)
Utils.Cache = require(script.Parent.SimulationCache)
Utils.Debug = require(script.Parent.Debug)
Utils.Net = require(script.Parent.Net)
Utils.Stream = require(script.Parent.Stream)
Utils.Data = require(script.Parent.SimulationData)
Utils.Runtime = require(script.Parent.SimulationRuntime)
Utils.Render = require(script.Parent.Render)

return Utils
