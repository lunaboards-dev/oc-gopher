local gopher = require("gopher")
local term = require("term")
local event = require("event")
local browser = require("gobrowse.browser")
local quit

if not gopher.has_minitel() and not gopher.has_internet() then
	io.stderr:write("gopher requires either an internet card or minitel to be installed\n")
	os.exit(1)
end

local args, opts = require("shell").parse(...)

if opts.h or #args ~= 1 then
	io.stderr:write("Usage: gotui <url>\n")
	os.exit(1)
end

local hooked_funcs = {}
local events = {}
for k, v in pairs(events) do

end

local brow = browser.new("gopher")
local function err_handler(err)
	brow:internal_error("Internal Lua error", debug.traceback(err):gsub("\t", "  "))
end
xpcall(function()

end, err_handler)
while true do
	xpcall(function()
		
	end, err_handler)
	os.sleep(gopher.min_sleep)
end