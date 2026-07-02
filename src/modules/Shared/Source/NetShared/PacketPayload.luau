local require = require(script.Parent.loader).load(script)

local PacketPayload = {} :: any

export type Payload = {
	Count: number,
	NilIndices: { number },
	Values: { any },
}

local function isPositiveInteger(value: any): boolean
	return typeof(value) == "number" and value >= 0 and value % 1 == 0
end

function PacketPayload.Pack(...: any): Payload
	local count = select("#", ...)
	local nilIndices: { number } = {}
	local values: { any } = {}
	local valueIndex = 1

	for index = 1, count do
		local value = select(index, ...)
		if value == nil then
			table.insert(nilIndices, index)
		else
			values[valueIndex] = value
			valueIndex += 1
		end
	end

	return {
		Count = count,
		NilIndices = nilIndices,
		Values = values,
	}
end

function PacketPayload.Unpack(payloadRaw: any): (number, { any })
	if typeof(payloadRaw) ~= "table" then
		return 0, {}
	end

	local payload = payloadRaw :: any
	local countRaw = payload.Count
	if not isPositiveInteger(countRaw) then
		return 0, {}
	end

	local count = countRaw :: number
	local nilIndices = if typeof(payload.NilIndices) == "table" then payload.NilIndices else {}
	local values = if typeof(payload.Values) == "table" then payload.Values else {}
	local unpacked: { any } = table.create(count)
	local nilCursor = 1
	local valueCursor = 1

	for index = 1, count do
		if nilIndices[nilCursor] == index then
			nilCursor += 1
			unpacked[index] = nil
		else
			unpacked[index] = values[valueCursor]
			valueCursor += 1
		end
	end

	return count, unpacked
end
return PacketPayload
