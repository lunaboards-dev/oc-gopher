local mt = require("minitel")
local thread = require("thread")
local fs = require("filesystem")
local event = require("event")
local coros = {}

local cfg = {
	port = 70,
	path = "/etc/srv/gopher",
	index = "gophermenu",
	enable_cgi = true
}

local function debug_sig(...)
	require("computer").pushSignal(...)
end

local function write_line(sock, type, display, resource, host, port, ext)
	sock:write(string.format("%s%s\t%s\t%s\t%s\t%s\r\n", tostring(type), display:gsub("\t", "  "), resource or "(NULL)", host or "no.host", tostring(port or "0")))
	require("computer").pushSignal("gopher_send", tostring(type), display:gsub("\t", "  "), resource or "(NULL)", host or "no.host", tostring(port or "0"))
	os.sleep(0)
end

local function close(sock, no_writeout)
	if not no_writeout then sock:write(".\r\n") end
	sock:close()
end

local function serve_error(sock, msg, info)
	write_line(sock, "3", msg)
	for line in info:gmatch("[^\n]*") do
		write_line(sock, "i", line)
	end
end

local function serve_file(sock, path)
	local h = io.open(path, "r")
	while true do
		local c = h:read(2048)
		if not c or c == "" then break end
		sock:write(c)
		os.sleep(0)
	end
end

local function cgi_wrap(sock, func)
	return function(...)
		return func(sock, ...)
	end
end

local function handle_connection(sock)
	xpcall(function()
		local path
		while path:sub(#path-1) ~= "\r\n" do
			coroutine.yield()
			path = path .. (sock:read(1) or "")
		end
		path = path:gsub("\r\n", "")
		local args
		if path:find("[\t%?]") then
			path, args = path:match("^([^\t%?]+)[\t%?](.+)$")
		end
		debug_sig("go_path", path)
		local cpath = fs.canonical(path)
		if path:match("^/%d/") then
			path = path:sub(4)
		end
		local fpath = cfg.path.."/"..path
		if path:match("%.cgi$") then
			-- CGI
			local spath = cfg.path.."/"..cpath:gsub("%.cgi$", ".lua")
			if not fs.exists(spath) then
				serve_error(sock, string.format("\"%s\" not found!", path), "the requested resource wasn't found")
				close(sock)
			end
			xpcall(function()
				assert(loadfile(spath)){
					args = args,
					write_line = cgi_wrap(sock, write_line),
					close = cgi_wrap(sock, close),
					serve_error = cgi_wrap(sock, serve_error),
					raw_write = cgi_wrap(sock, sock.write)
				}
			end, function(err)
				serve_error(sock, "lua error in "..spath, debug.traceback(err))
			end)
		elseif fs.exists(fpath) then
			if fs.isDirectory(fpath) and not fs.exists(fpath.."/"..cfg.index) then
				serve_error(sock, string.format("found \"%s\" with no menu!", path), "no gophermenu found for this directory")
				close(sock)
			elseif fs.isDirectory(fpath) then
				local f = io.open(fpath.."/"..cfg.index, "r")
				for line in f:lines() do
					sock:write(line.."\r\n")
					os.sleep(0.0001)
				end
				close(sock)
			else
				serve_file(sock, fpath)
				close(sock, true)
			end
		end
	end, function(err)
		io.stderr:write(debug.traceback(err))
	end)
end

local l
function start()
	l = mt.flisten(70, function(sock)
		table.insert(coros, thread.create(handle_connection, sock))
	end)
	event.push("dans_add_service", "minitel", cfg.port, "web/gopher", "gopher server")
end

function stop()
	require("event").ignore("net_msg", l)
	event.push("dans_add_service", "minitel", cfg.port, "web/gopher", "gopher server")
end