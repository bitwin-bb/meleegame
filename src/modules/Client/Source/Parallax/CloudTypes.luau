local require = require(script.Parent.loader).load(script)

local CloudServiceUtils = require("CloudServiceUtils")

local CloudTypes = {}

export type CloudAssetDefinition = CloudServiceUtils.CloudAssetDefinition
export type CloudSurfaceState = CloudServiceUtils.CloudSurfaceState
export type CloudView = CloudServiceUtils.CloudView

return CloudTypes
