local gopher = require("gopher")
local term = require("term")
local event = require("event")
local browser = require("gobrowse.browser")
local computer = require("computer")
local quit

if not gopher.has_minitel() and not gopher.has_internet() then
	io.stderr:write("gopher requires either an internet card or minitel to be installed\n")
	os.exit(1)
end

local args, opts = require("shell").parse(...)

if opts.h then
	io.stderr:write("Usage: gopher [url]\n")
	os.exit(0)
end

local hooked_funcs = {}
local events = {}

local brow = browser.new("gopher")
local function err_handler(err)
	--[[brow:clear()
	io.stderr:write("Internal Lua error\n"..debug.traceback(err):gsub("\t", "  "))
	brow.quit = true]]
	brow:internal_error("Internal Lua error", debug.traceback(err):gsub("\t", "  "))
end

function events.key_down(_, key, code)
	brow:key_down(key, code)
end
--brow.texterror = true
xpcall(function()
	if args[1] then
		brow:navigate(args[1], true)
	else
		--brow:internal_error("test", "test2")
		term.clear()
	end
	brow:draw()
end, err_handler)
while not brow.quit do
	local rtv = table.pack(computer.pullSignal(gopher.min_sleep))
	xpcall(function()
		if rtv[1] and events[rtv[1]] then
			events[rtv[1]](table.unpack(rtv, 2))
			brow:draw()
		end
		--brow:draw()
	end, err_handler)
end