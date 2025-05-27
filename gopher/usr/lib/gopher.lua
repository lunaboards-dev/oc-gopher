local event = require("event")
local has_mt, mt = pcall(require, "mtv2")
--local net = require("internet")
local component = require("component")
local has_net = component.isAvailable("internet")

local gopher = {}
local sock = {}

function sock:write(dat)
	return self.sock.write(dat)
end

function sock:read(amt)
	if #self.buffer == 0 and self.closed then return end
	if amt == true then -- This looks dumb but, trust me, it's requried
		local rdat = self.buffer
		self.buffer = ""
		return rdat
	end
	--local req_buffer = #self.buffer-amt+1
	self.buffer_request = amt
	while #self.buffer < amt and not self.closed do
		--self.buffer_request = req_buffer
		event.push("buffer_empty")
		event.pull("buffer_filled")
	end
	--print("return")
	local bsize = #self.buffer
	local rdat = self.buffer:sub(1, math.min(bsize, amt))
	self.buffer = self.buffer:sub(math.min(bsize, amt)+1)
	self.stat_read = (self.stat_read or 0) + #rdat
	return rdat
end

function sock:close()
	if self.realclose then return end
	self.realclose = true
	self.closed = true
	self.sock.close()
	event.ignore("internet_ready", self.helper)
	event.ignore("buffer_empty", self.helper)
end

local function tcpopen(addr, port, noinit)
	local s = {
		sock = component.internet.connect(addr, port),
		buffer = "",
		stat_read = 0,
		--buffer_request = 4096
	}
	function s.helper()
		--print("ready")
		if #s.buffer >= math.max(s.buffer_request or 4096, 4096) then
			--event.push("buffer_filled")
			return
		end
		while true do
			local r = s.sock.read()
			if not r then
				s.closed = true
				--print("closed")
				break
			end
			s.buffer = s.buffer .. r
			if #s.buffer >= math.max(s.buffer_request or 4096, 4096) then
				break
			end
			if #r == 0 then break end
		end
		event.push("buffer_filled")
	end
	event.listen("internet_ready", s.helper)
	event.listen("buffer_empty", s.helper)
	local ok, con
	while not con do
		ok, con = pcall(s.sock.finishConnect)
		if not ok then
			return nil, con
		end
		os.sleep(gopher.min_sleep)
	end
	s.helper()
	setmetatable(s, {__index=sock})
	table.insert(require("process").info().data.handles, s)
	return s
end

gopher.min_sleep = 0.0001
gopher.dont_strip_leading_slash = false

local function minsleep()
	os.sleep(gopher.min_sleep)
end

function gopher.parse_url(url)
	local proto = url:match("^(%a+)://")
	if not proto then
		proto = "gopher"
	else
		url = url:sub(#proto+4)--url:match("://(.+)$")
	end
	local port = url:match(":(%d+)/?")
	local rsc, host
	if port then
		host = url:match("^([^:/]+)")
		port = tonumber(port, 10)
		if not port then return nil, "unable to parse port" end
		rsc = url:match("^[^/]+(/.+)")
		if not rsc then
			rsc = "/"
		end
	else
		host, rsc = url:match("^([^/]+)(/.+)")
		if not host then
			host = url
			rsc = "/"
		end
		port = proto == "gomt" and 80 or 70
	end
	local hint
	if rsc and rsc:match("/%d/") then
		hint = rsc:sub(2,2)
		rsc = rsc:sub(3)
	end
	if proto ~= "gopher" and proto ~= "gomt" and proto ~= "about" then return nil, "bad protocol" end
	if not gopher.dont_strip_leading_slash and rsc then
		rsc = rsc:gsub("^/", "")
	end
	return {
		proto = proto,
		host = host,
		port = port,
		rsc = rsc,
		hint = hint
	}
end

function gopher.req(url, hint)
	local p, err
	if type(url) == "string" then
		p, err = gopher.parse_url(url)
	else
		p = url
	end
	if not p then return p, err end
	local sock
	if p.proto == "gopher" then
		--sock = net.open(p.host, p.port)
		sock, err = tcpopen(p.host, p.port, p.hint == "9")
	elseif p.proto == "gomt" then
		sock, err = mt.open(p.host, p.port)
	end
	if not sock then
		return sock, err
	end
	hint = hint or p.hint
	sock:write(p.rsc.."\r\n")

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

	local function text_xfer(buffer)
		while true do
			minsleep()
			local c = sock:read(4096)
			if not c then break end
			buffer = buffer .. c
		end
		return buffer:gsub("\n\n", "\n"):gsub("\n%.\r?\n?$", "")
	end

	local function file_xfer(buffer)
		return sock, true, buffer
	end

	local function fast_menu_xfer(lines, buf)
		while true do
			minsleep()
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

	-- Attempt to autodetect what we're trying to request.
	local function detect_xfer()
		local buffer = ""
		local parsed_lines = {proto = p.proto}
		local allowed_bin = {
			[9] = true,
			[10] = true,
			[13] = true
		}
		while true do
			local c
			minsleep()
			c = sock:read(128)
			if not c then
				return nil, "unexpected close"
			end
			buffer = buffer .. c
			local bufsize = #buffer
			for i=1, 128 do
				local b = buffer:byte(bufsize-i+1)
				if (b < 32 or b > 127) and not allowed_bin[b] then
					-- Binary file
					return file_xfer(buffer)
				end
			end
			local line_end, nl_end
			repeat
				line_end, nl_end = buffer:find("\r\n", 1, true)
				local first = buffer:sub(1,1)
				if line_end then
					local tab_char = buffer:find("\t", 1, true)
					if not tab_char and first ~= "i" then
						return text_xfer(buffer)
					end
					if parse_line(parsed_lines, buffer:sub(1, line_end-1)) then
						return parsed_lines
					end
					buffer = buffer:sub(nl_end+1)
				end
			until not line_end
			if #parsed_lines > 0 then
				return fast_menu_xfer(parsed_lines, buffer)
			end
		end
	end
	if not hint then
		return detect_xfer()
	elseif hint == "1" or hint == "7" then
		return fast_menu_xfer({proto = p.proto}, "")
	elseif hint == "0" then
		return text_xfer("")
	elseif bin_file_hints[hint] then
		return file_xfer("")
	else
		return nil, "unknown type"
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