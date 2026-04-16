--!strict
local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)

local Promise = require("Promise")

type StateGetter<T> = () -> T
type StateApplier<T> = (nextStateRaw: any) -> T
type StateChangedHandler = (nextStateRaw: any) -> ()

local ServiceSync = {}

local function requestSyncPromise(serviceClientRaw: any): any
	if typeof(serviceClientRaw) ~= "table" then
		return Promise.resolved(false)
	end
	if typeof((serviceClientRaw :: any).requestSync) ~= "function" then
		return Promise.resolved(false)
	end

	return Promise.spawn(function(resolve, _reject)
		local success = pcall(function()
			(serviceClientRaw :: any):requestSync()
		end)
		resolve(success)
	end)
end

function ServiceSync.syncFromService<T>(
	serviceClientRaw: any,
	getFallbackState: StateGetter<T>,
	applyState: StateApplier<T>
): T
	if typeof(serviceClientRaw) ~= "table" or (serviceClientRaw :: any).state == nil then
		return getFallbackState()
	end

	local success, nextState = pcall(function()
		return (serviceClientRaw :: any):getState()
	end)
	if success then
		return applyState(nextState)
	end

	return getFallbackState()
end

function ServiceSync.ConnectStateChanged(
	serviceClientRaw: any,
	onStateChanged: StateChangedHandler
): RBXScriptConnection?
	if typeof(serviceClientRaw) ~= "table" then
		return nil
	end
	local stateChangedSignal = (serviceClientRaw :: any).stateChanged
	if stateChangedSignal == nil then
		return nil
	end

	return stateChangedSignal:Connect(onStateChanged)
end

function ServiceSync.ReadReady(serviceClientRaw: any, fallbackReadyRaw: any?): boolean
	local fallbackReady = fallbackReadyRaw == true
	if typeof(serviceClientRaw) ~= "table" then
		return fallbackReady
	end
	if typeof((serviceClientRaw :: any).isReady) ~= "function" then
		return fallbackReady
	end

	local success, isReady = pcall(function()
		return (serviceClientRaw :: any):isReady()
	end)
	if not success then
		return fallbackReady
	end
	return isReady == true
end

function ServiceSync.RequestSync(serviceClientRaw: any)
	requestSyncPromise(serviceClientRaw)
end

function ServiceSync.RequestSyncMany(serviceClientsRaw: { any })
	for _, serviceClient in serviceClientsRaw do
		requestSyncPromise(serviceClient)
	end
end

ServiceSync.connectStateChanged = ServiceSync.ConnectStateChanged
ServiceSync.readReady = ServiceSync.ReadReady
ServiceSync.requestSync = ServiceSync.RequestSync
ServiceSync.requestSyncMany = ServiceSync.RequestSyncMany

return ServiceSync
