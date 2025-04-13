local has_mt, mt = pcall(require, "minitel")
--local component = require("component")
--local has_net, net = pcall(component.getPrimary, "internet")
local net = require("internet")

local gopher = {}

--- Parses a gopher URL
--- @param url string URL to parse
--- @return table|nil proto Parsed URL or nil if invalid.
--- @return string? err Error message
function gopher.parse_url(url)
	local proto = url:match("^(go%a+)://")
	if not proto then
		proto = "gopher"
	else
		url = url:match("://(.+)$")
	end
	local port = url:match(":(%d+)/?")
	local rsc, host
	if port then
		host = url:match("^([^:]+)")
		port = tonumber(port, 10)
		if not port then return nil, "unable to parse port" end
		rsc = url:match("^[^/]+(.+)")
		if not rsc then
			rsc = "/"
		end
	else
		host, rsc = url:match("^([^/]+)(.+)")
		port = 70
	end
	local hint
	if rsc:match("/%d/") then
		hint = rsc:sub(2,2)
		rsc = rsc:sub(3)
	end
	if proto ~= "gopher" and proto ~= "gomt" then return nil, "bad protocol" end
	return {
		proto = proto,
		host = host,
		port = port,
		rsc = rsc,
		hint = hint
	}
end

--[[function gopher.transfer_file(url)

end]]



--- Sends a gopher request.
---@param url string URL for resource. Start with `gomt://` for a minitel address, or `gopher://` for an internet address (though this is the default). Port can also be specified with `:port`, though the default is port 70.
---@param hint? string Entry type for this resource. Not required, and can be gleamed from the URL.
---@return table|string|nil response Parsed gophermap for request, socket if it's a binary file, string if it's text, or nil if there's an error
---@return string|boolean|nil errtext Error message or true if it's a file
---@return string? buffer Current buffer if it's a file
function gopher.req(url, hint)
	local p, e = gopher.parse_url(url)
	if not p then return p, e end
	local sock
	if p.proto == "gomt" then
		sock, e = mt.open(p.host, p.port)
		if not sock then return sock, e end
		os.sleep(0)
	elseif p.proto == "gopher" then
		sock, e = net.socket(p.host, p.port)
		if not sock then return sock, e end
	else
		return nil, "bad protocol"
	end
	hint = hint or p.hint
	sock:write(p.rsc.."\r\n")
	local function text_xfer(buffer)
		while true do
			os.sleep(0.0001)
			local c = sock:read(4096)
			if p.proto == "gopher" and not c then break end
			if p.proto == "gomt" and sock.state == "closed" then break end
			if c then
				buffer = buffer .. c
			end
		end
		return (buffer:gsub("\n\n", "\n"))
	end
	local function file_xfer(buffer)
		return sock, true, buffer
	end
	local bin_file_hints = {
		["4"] = true,
		["5"] = true,
		["6"] = true,
		["9"] = true,
		g = true,
		I = true
	}
	local function parse_line(lines, linebuf)
		if not linebuf or linebuf == "." then
			return true
		elseif linebuf == "" then
			table.insert(lines, {})
		else
			local fields = {"display", "rsc", "host", "port"}
			local line = {ext={}}
			local i = 1
			line.type = linebuf:sub(1,1)
			for field in linebuf:sub(2):gmatch("[^\t]*") do
				if fields[i] then
					line[fields[i]] = field
				else
					table.insert(line.ext, field)
				end
				i = i + 1
			end
			if line.port then
				line.port = tonumber(line.port, 10)
			end
			table.insert(lines, line)
		end
	end
	local function net_menu_xfer(lines)
		local buf = ""
		while true do
			os.sleep(0.001)
			local c = sock:read(math.huge)
			if not c then break end
			buf = buf .. c
		end
		local next = 1
		while true do
			local st, en = buf:find("\r\n", next)
			if not st then st = #buf+1 end
			local linebuf = buf:sub(next, st-1)
			if parse_line(lines, linebuf) then break end
			if not en then break end
			next = en + 1
		end
		return lines
	end
	local function fast_menu_xfer(lines)
		while true do
			local linebuf
			while not linebuf do
				linebuf = sock:read()
				os.sleep(0.001)
			end
			linebuf = linebuf:gsub("\r", "")
			if parse_line(lines, linebuf) then break end
		end
		return lines
	end
	local function menu_xfer()
		local linebuf = ""
		local parsed_lines = {proto = p.proto}
		local allowed_bin = {
			["\t"] = true,
			["\n"] = true,
			["\r"] = true
		}
		while true do
			local c
			while p.proto == "gomt" and not c do
				os.sleep(0.0001)
				c = sock:read(1)
			end
			if p.proto == "gopher" then
				os.sleep(0.0001)
				c = sock:read(1)
			end
			if c and #c > 0 and (c:byte() < 32 or c:byte() > 127) and not allowed_bin[c] then
				-- File is binary
				return file_xfer(linebuf..c)
			elseif (linebuf:sub(#linebuf, #linebuf) == "\r" and c == "\n") or not c then
				local fields = {"display", "rsc", "host", "port"}
				local line = {ext={}}
				local i = 1
				if #linebuf > 1 and linebuf:sub(1,1) ~= "i" and not linebuf:find("\t") then
					-- File is text. Proceed in text xfer mode.
					return text_xfer(linebuf..c)
				elseif linebuf == "\r" then
					table.insert(parsed_lines, {})
					goto continue
				end
				line.type = linebuf:sub(1,1)
				for field in linebuf:sub(2):gmatch("[^\t]*") do
					if fields[i] then
						line[fields[i]] = field
					else
						table.insert(line.ext, field)
					end
					i = i + 1
				end
				if line.port then
					line.port = tonumber(line.port, 10)
				end
				table.insert(parsed_lines, line)
				::continue::
				os.sleep(0)
				return p.proto == "gopher" and net_menu_xfer(parsed_lines) or fast_menu_xfer(parsed_lines)
				--return net_menu_xfer(parsed_lines)
				--linebuf = ""
			elseif #linebuf == 0 and c == "." then
				break
			else
				linebuf = linebuf .. c
			end
		end
		return parsed_lines
	end
	if not hint then
		return menu_xfer()
	end
	if hint == "1" or hint == "7" then
		return p.proto == "gopher" and net_menu_xfer({proto = p.proto}) or fast_menu_xfer({proto = p.proto})
	elseif hint == "0" then
		return text_xfer("")
	elseif bin_file_hints[hint] then
		return file_xfer("")
	else
		error "unknown type"
	end
end

--- Check for Minitel
---@return boolean ok True if minitel is installed.
function gopher.has_minitel()
	return has_mt
end

--- Check for internet card
---@return boolean ok True of internet card is installed.
function gopher.has_internet()
	return require("component").isAvailable("internet")
end

return gopher