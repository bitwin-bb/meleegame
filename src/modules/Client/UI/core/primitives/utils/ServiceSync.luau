local require = require(script.Parent.loader).load(script)

local Promise = require("Promise")

local function fulfilledPromise(...): any
	local args = table.pack(...)
	return Promise.new(function(fulfill)
		fulfill(table.unpack(args, 1, args.n))
	end)
end

type StateGetter<T> = () -> T
type StateApplier<T> = (nextStateRaw: any) -> T
type StateChangedHandler = (nextStateRaw: any) -> ()

local ServiceSync = {}

local function requestSyncPromise(serviceClientRaw: any): any
	if typeof(serviceClientRaw) ~= "table" then
		return fulfilledPromise(false)
	end
	if typeof((serviceClientRaw :: any).RequestSync) ~= "function" then
		return fulfilledPromise(false)
	end

	return Promise.spawn(function(fulfill, _reject)
		local success = pcall(function()
			(serviceClientRaw :: any):RequestSync()
		end)
		fulfill(success)
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
		return (serviceClientRaw :: any):GetState()
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
	if typeof((serviceClientRaw :: any).IsReady) ~= "function" then
		return fallbackReady
	end

	local success, isReady = pcall(function()
		return (serviceClientRaw :: any):IsReady()
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
return ServiceSync
