--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Utils = {}

Utils.Shared = require(gameRoot.Shared.Features.worldGeneration.simulation.Shared)
Utils.Config = require(gameRoot.Shared.Features.worldGeneration.simulation.SimulationConfig)
Utils.State = require(gameRoot.Shared.Features.worldGeneration.simulation.SimulationState)
Utils.Cache = require(gameRoot.Shared.Features.worldGeneration.simulation.SimulationCache)
Utils.Debug = require(gameRoot.Shared.Features.worldGeneration.simulation.Debug)
Utils.Net = require(gameRoot.Shared.Features.worldGeneration.simulation.Net)
Utils.Stream = require(gameRoot.Shared.Features.worldGeneration.simulation.Stream)
Utils.Data = require(gameRoot.Shared.Features.worldGeneration.simulation.SimulationData)
Utils.Runtime = require(gameRoot.Shared.Features.worldGeneration.simulation.SimulationRuntime)
Utils.Render = require(gameRoot.Shared.Features.worldGeneration.simulation.Render)

return Utils
