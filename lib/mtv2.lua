local computer = require "computer"
local event = require "event"
local net = {}
net.mtu = 8192
net.timeout = 30
net.minport = 32768
net.maxport = 65535
net.openports = {}
net.min_sleep = 0.001 -- This is a hack because of a bug I ran into

net.tracker = setmetatable({}, {__mode="kv"})
net.sockets = {}

local function reap()
	local to_remove = {}
	for k, v in pairs(net.sockets) do
		if not net.tracker[v] then
			v:close()
			table.insert(to_remove, k)
		end
	end
	for i=1, #to_remove do
		net.sockets[to_remove[i]] = nil
	end
end

for k, v in pairs(computer.getDeviceInfo()) do
	if v.class == "network" then
		net.mtu = math.min(net.mtu, tonumber(v.capacity))
	end
end

--- Generates a random packet ID. This shouldn't ever manage to repeat unless all computers turned on at exactly the same time and some extreme bullshit happens.
---@return string id Random packet ID
function net.gen_packet_id()
	return tostring(os.time()*os.clock()*math.random())
end

--- Sends an unreliable packet.
--- @param to string Address to send to
--- @param port number Port to send to
--- @param data string Data to send.
--- @param pktid string? Packet ID.
--- @return string id Packet ID.
function net.usend(to, port, data, pktid)
	pktid = pktid or net.gen_packet_id()
	computer.pushSignal("net_send", 0, to, port, data, pktid)
	return pktid
end

--- Send a reliable packet
--- @param to string Address to send to.
--- @param port number Port to send to
--- @param data string Data to send
--- @param block boolean Set to true for nonblocking.
--- @return boolean|string success_or_pktid True if the packet was successfuly sent, or the pakcet ID if nonblocking.
function net.rsend(to, port, data, block)
	local pid, stime = net.gen_packet_id(), computer.uptime() + net.timeout
	computer.pushSignal("net_send", 1, to, port, data, pid)
	if block then return pid end
	local rpid
	repeat
		_,rpid = event.pull(net.min_sleep, "net_ack")
	until rpid == pid or computer.uptime() > stime
	if not rpid then return false end
	return true
end

function net.send(to, port, data)

end

function net.open(to, port)

end

function net.listen(port)

end

function net.flisten(port, listener)

end

return net