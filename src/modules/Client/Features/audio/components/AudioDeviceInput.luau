--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")

local FusionUtils = require(gameRoot.Client.Features.audio.modules.fusionUtils)

return FusionUtils.CreateInstanceWrapper("AudioDeviceInput", "AudioDeviceInput", require(quentyPackages.maid.Shared.Maid))
