local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuffRightSideBar = require("BuffRightSideBar")
local BuffSlice = require("BuffSlice")
local React = require(ReplicatedStorage.Packages.React)
local Table = require("Table")
local useStore = require("useCoreStore")

export type BuffRootProps = {
	records: { any }?,
	useServiceState: boolean?,
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	iconSize: number?,
	DebugInnerBounds: boolean?,
	debugInnerBounds: boolean?,
	native: { [any]: any }?,
}

local e: typeof(React.createElement) = React.createElement

local function cloneRecords(recordsRaw: any): { any }
	if typeof(recordsRaw) ~= "table" then
		return {}
	end

	return Table.copy(recordsRaw :: { any })
end

return function(props: BuffRootProps): React.ReactNode
	local useServiceState = props.useServiceState ~= false and props.records == nil
	local serviceRecords = useStore(if useServiceState then BuffSlice.activeRecordsAtom else nil) :: { any }?
	local records = if useServiceState
		then cloneRecords(serviceRecords or BuffSlice.getActiveRecords())
		else cloneRecords(props.records)

	React.useEffect(function()
		if not useServiceState then
			return
		end

		local BuffThunks = require("BuffThunks")
		local stop = BuffThunks.Start()

		return function()
			stop()
		end
	end, { useServiceState })

	return e(BuffRightSideBar, {
		records = records,
		layoutOrder = props.layoutOrder,
		visible = props.visible,
		zIndex = props.zIndex,
		size = props.size,
		position = props.position,
		anchorPoint = props.anchorPoint,
		iconSize = props.iconSize,
		DebugInnerBounds = props.DebugInnerBounds,
		debugInnerBounds = props.debugInnerBounds,
		native = props.native,
	})
end
