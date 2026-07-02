
local require = require(script.Parent.loader).load(script)

local Utils = {}

Utils.Shared = require("Shared")
Utils.Config = require("SimulationConfig")
Utils.State = require("SimulationState")
Utils.Cache = require("SimulationCache")
Utils.Debug = require("WorldSimulationDebug")
Utils.Net = require("Net")
Utils.Stream = require("Stream")
Utils.Data = require("SimulationData")
Utils.Runtime = require("SimulationRuntime")
Utils.Render = require("WorldSimulationRender")

return Utils
