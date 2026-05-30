--!strict

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local FusionUtils = require(script:FindFirstAncestor("game").Client.Features.audio.modules.fusionUtils)

return FusionUtils.CreateInstanceWrapper("AudioGate", "AudioGate", loader("Maid"))
