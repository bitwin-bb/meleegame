local require = require(script.Parent.loader).load(script)
local function isEarlyPlayerChannelError(errRaw: any): boolean
	local err = tostring(errRaw)
	return string.find(err, "bufferWriter", 1, true) ~= nil and string.find(err, "size", 1, true) ~= nil
end

local function bindServerSendRetry(serviceName: string, methodName: string, packet: any)
	local sendTo = packet.sendTo
	if typeof(sendTo) ~= "function" then
		return
	end

	packet.sendTo = function(data: any, player: Player)
		local ok, err = pcall(sendTo, data, player)
		if ok then
			return
		end
		if not isEarlyPlayerChannelError(err) then
			warn(`ByteNet send failed for {serviceName}.{methodName}: {tostring(err)}`)
			return
		end

		task.defer(function()
			local retryOk, retryErr = pcall(sendTo, data, player)
			if not retryOk then
				warn(`ByteNet send retry failed for {serviceName}.{methodName}: {tostring(retryErr)}`)
			end
		end)
	end
end

local function bindServerPacketRetries(packets: { [string]: any })
	for serviceName, servicePackets in packets do
		if typeof(servicePackets) == "table" then
			for methodName, packet in servicePackets do
				if typeof(packet) == "table" then
					bindServerSendRetry(serviceName, methodName, packet)
				end
			end
		end
	end
end

local Packets = table.clone(require("NetPacketsShared")) :: any

bindServerPacketRetries(Packets)

function Packets.Init(): ()
	return
end
return Packets
