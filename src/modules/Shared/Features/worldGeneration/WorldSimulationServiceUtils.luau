--!strict

local Utils = {}

Utils.Shared = require(script.Parent.simulation.Shared)
Utils.Config = require(script.Parent.simulation.SimulationConfig)
Utils.State = require(script.Parent.simulation.SimulationState)
Utils.Cache = require(script.Parent.simulation.SimulationCache)
Utils.Debug = require(script.Parent.simulation.Debug)
Utils.Net = require(script.Parent.simulation.Net)
Utils.Stream = require(script.Parent.simulation.Stream)
Utils.Data = require(script.Parent.simulation.SimulationData)
Utils.Runtime = require(script.Parent.simulation.SimulationRuntime)
Utils.Render = require(script.Parent.simulation.Render)

return Utils
