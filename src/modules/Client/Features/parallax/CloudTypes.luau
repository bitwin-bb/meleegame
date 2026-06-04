--!strict

local CloudServiceUtils = require(script.Parent.CloudServiceUtils)

local CloudTypes = {}

export type CloudAssetDefinition = CloudServiceUtils.CloudAssetDefinition
export type CloudSurfaceState = CloudServiceUtils.CloudSurfaceState
export type CloudView = CloudServiceUtils.CloudView

return CloudTypes
