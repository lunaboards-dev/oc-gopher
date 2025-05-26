local term = require("term")
local utils = require("gobrowse.util")
local gopher= require("gopher")
local event = require("event")
local thread = require("thread")
local fs = require("filesystem")
local builder = require("gobrowse.pagebuild")
local ser = require("serialization")
local uptime = require("computer").uptime
local browser = {
	internal = {}
}

local function bit_depth()
	return term.gpu().getDepth()
end

local spinner = {
	"|",
	"/",
	"-",
	"\\"
}

function browser.new(brow)
	local rt = setmetatable({
		browser = brow,
		url = "Home",
		history = {},
		state = "text",
		textlines="gopher browser.\nPress G to navigate to a new page.",
		offset = 0,
		lcount = 2,
		query = ""
	}, {__index=browser})
	rt:load_bookmarks()
	rt:navigate("about://home")
	local function timer()
		local stat = "✔"
		if rt.loading then
			stat = " "..spinner[math.floor(os.clock()*5)%4+1]
		end
		rt:update_taskbar(stat)
	end
	--rt.timer = event.timer(0.1, timer, math.huge)
	function rt.err_handler(err)
		--[[brow:clear()
		io.stderr:write("Internal Lua error\n"..debug.traceback(err):gsub("\t", "  "))
		brow.quit = true]]
		rt:internal_error("Internal Lua error", debug.traceback(err):gsub("\t", "  "))
	end
	rt.helpers = {}
	function rt.helpers.key_down(_, _, key, code)
		xpcall(function()
			rt:key_down(key, code)
			rt:draw()
		end, rt.err_handler)
	end
	function rt.helpers.scroll(_, _, x, y, amt)
		xpcall(function()
			rt:scroll(x, y, amt)
			rt:draw()
		end, rt.err_handler)
	end
	for k, v in pairs(rt.helpers) do
		event.listen(k, v)
	end
	table.insert(require("process").info().data.handles, rt)
	-- Draw for the first time
	rt:draw()
	return rt
end

function browser:spinner()
	local stat = "✔"
	if self.loading then
		stat = " "..spinner[math.floor(os.clock()*5)%4+1]
	elseif self.error_state then
		stat = "⚠"
	end
	return stat
end

function browser:draw_spinner()
	local w, h = term.getViewport()
	local x, y = term.getCursor()
	term.setCursor(1, h)
	term.write(string.format("\27[47;30m%s\27[0m", self:spinner()))
	term.setCursor(x, y)
end

function browser:termread(...)
	self.ignore_keys = true
	local dat, err = term.read(...)
	self.ignore_keys = false
	return dat, err
end

function browser:close()
	if self.fullclosed then return end
	self.fullclosed = true
	for k, v in pairs(self.helpers) do
		event.ignore(k, v)
	end
	--event.cancel(self.timer)
end

function browser:update_taskbar(status)
	local w, h = term.getViewport()
	term.setCursor(1, h)
	term.write("\27[47;30m")
	term.clearLine()
	term.write(utils.uclamp(string.format("%s %s | %s", status, self.browser, utils.replace_tab(self.url)), w-1))
	term.write("\27[0m")
end

function browser:push_history(page)
	table.insert(self.history, page)
end

function browser:pop_history()
	return table.remove(self.history)
end

function browser:display_history()
	local w, h = term.getViewport()
	local vw = w/2
	local vh = h-1
	for i=1, vh do
		local history_ent = self.history[#self.history-i+1]
		local y = h-i
		
	end
end

local codes = {
	[208] = "down",
	[200] = "up",
	[203] = "left",
	[205] = "right",
	[201] = "pgup",
	[209] = "pgdn"
}

local function rewrite_line(y, msg)
	term.setCursor(1, y)
	term.clearLine()
	term.write(msg)
end

local function draw_link(y, sym, str, selected, dcolor, w)
	local dstr = utils.uclamp(str, w)
	if selected then
		if bit_depth() == 1 then
			rewrite_line(y, string.format("%s \27[47;30m%s\27[0m", sym, dstr))
		else
			rewrite_line(y, string.format("%s \27[33m%s\27[0m", sym, dstr))
		end
	else
		rewrite_line(y, string.format("%s \27[%dm%s\27[0m", sym, dcolor, dstr))
	end
end

local function draw_search(y, str, query, selected, w)
	draw_link(y, "🔍", str, selected, 35, w)
	term.write(": "..utils.uclamp(query, w-(term.getCursor()+1)))
end

function browser:draw_text()
	local lines = utils.explode(self.textlines, "[^\n]+")
	local w, h = term.getViewport()
	local vh = h-1
	for i=1, vh do
		local ri = i+self.offset
		rewrite_line(i, lines[ri] or "")
	end
end

local settings = {
	buttongrp = {},
	text = {},
	number = {},
	checkbox = {},
	bookmark = {},
	history = {}
}

local etypes = {
	["0"] = "📝",
	["1"] = "📁",
	["2"] = "☏",
	["3"] = "\27[31m!!\27[0m",
	["4"] = " H",
	["5"] = "💻",
	["6"] = " U",
	["7"] = "<SEARCH>",
	["8"] = "🖥",
	["9"] = "💾",
	["+"] = "<ALT>",
	g = "📹",
	I = "🖼",
	T = "3270",
	[":"] = "BMP",
	[";"] = "📹",
	["<"] = "SND",
	d = "DOC",
	h = "🔗",
	i = "",
	p = "🖼",
	r = "RTF",
	s = "SND",
	P = "PDF",
	X = "XML",
	[settings.bookmark] = "★",
	[settings.text] = "🔧",
	[settings.number] = "🔧",
	[settings.checkbox] = "🔧",
	[settings.history] = "←"
	--[settings.bookmark] = "🔧",
}

local cant_navigate = {
	["2"] = true,
	["8"] = true,
	T = true,
	h = true
}

function browser:draw_menu()
	local w, h = term.getViewport()
	local vh = h-1
	for i=1, vh do
		local ri = i+self.offset
		local sel = ri == self.selected
		local ent = self.lines[ri]
		local txt = utils.uclamp(ent and ent.display or "", w-3)
		if not ent or not ent.type or ent.type == "+" then
			rewrite_line(i, "")
		elseif ent.type == "i" then
			rewrite_line(i, "   "..txt)
		elseif ent.type == "3" then
			rewrite_line(i, string.format("%s %s", etypes["3"], txt))
		elseif ent.type == "7" then
			draw_search(i, ent.display, self.query, sel, w)
		elseif cant_navigate[ent.type] then
			draw_link(i, etypes[ent.type], txt, sel, 31, w)
		else
			draw_link(i, etypes[ent.type], txt, sel, 36, w)
		end
	end
end

function browser:handle_internal(page)
	local pg = page:match("about://([^%?\t]+)")
	local arg = page:match("[%?\t](.+)")
	if browser.internal[pg] then
		local mode, data = browser.internal[pg](self, arg)
		self.state = mode
		if mode == "menu" then
			self.lines = data
			self:recompute_links()
		elseif mode == "text" then
			self.textlines = data
		end
	end
	return {
		proto = "about",
		host = pg,
		port = 70,
		rsc = "",
		hint = self.mode == "menu" and "1" or "0"
	}
end

function browser.internal:home(arg)
	local page = builder()
	page:print("Welcome to "..self.browser.."!")
	page:print("Controls:")
	page:print("    G: Open navigation prompt.")
	page:print("    H: Open history.")
	page:print("    K: Add/remove a bookmark.")
	page:print("    B: Open bookmarks.")
	page:print("    Q: Quit.")
	page:print("    ←: Back.")
	page:print("  →/↵: Follow link.")
	page:add("7", "Search Veronica-2", "v2/vs", "gopher.floodgap.com", 70)
	return "menu", page
end

function browser.internal:bookmarks(arg)
	local page = builder()
	page:print(string.format("Bookmarks (%d):", #self.bookmarks))
	for i=1, #self.bookmarks do
		local bm = self.bookmarks[i]
		page:add(settings.bookmark, bm.name, nil, nil, nil, bm)
	end
	return "menu", page
end

function browser.internal:history(arg)
	local page = builder()
	for i=#self.history, 1, -1 do
		local h = self.history[i]
		page:add(settings.history, h.display, nil, nil, nil, h)
	end
	return "menu", page
end

function browser.internal:config(arg)
	local page = builder()
	page:print("TODO: Add settings here.")
	return "menu", page
end

function browser:load_bookmarks()
	local bm_path = os.getenv("HOME").."/."..self.browser.."/bookmarks"
	if fs.exists(bm_path) then
		local f = io.open(bm_path, "r")
		local dat = f:read("*a")
		f:close()
		self.bookmarks = ser.unserialize(dat)
	else
		self.bookmarks = {}
	end
end

function browser:save_bookmarks()
	local ddir = os.getenv("HOME").."/."..self.browser
	if not fs.exists(ddir) then
		fs.makeDirectory(ddir)
	end
	local bm_path = os.getenv("HOME").."/."..self.browser.."/bookmarks"
	--[[if fs.exists(bm_path) then
		local f = io.open(bm_path, "r")
	else
		self.bookmarks = {}
	end]]
	local dat = ser.serialize(self.bookmarks)
	local f = io.open(bm_path, "w")
	f:write(dat)
	f:close()
end

function browser:reset()
	term.write("\27[0m")
end

function browser:clear()
	self:reset()
	term.clear()
end

function browser:nav_reset(history)
	self.url = history.url
	self.url_tbl = history.tbl
	self.selected = history.selected
	self.offset = history.offset
end

function browser:nlines()
	if self.state == "menu" then return #self.lines
	elseif self.state == "text" then return select(2, self.textlines:gsub("\n", ""))
	end return 0
end

function browser:recompute_links()
	local not_link = {
		i = true,
		["+"] = true
	}
	self.links = {}
	for i=1, #self.lines do
		local line = self.lines[i]
		if line.type and not not_link[line.type] then
			table.insert(self.links, i)
		end
	end
end

function browser:draw()
	if self.ignore_keys then return end
	if self.state == "menu" then
		self:draw_menu()
	elseif self.state == "text" then
		self:draw_text()
	elseif self.state == "history" then
		self:display_history()
	end
	local stat = self:spinner()
	self:update_taskbar(stat)
end

function browser:menubar_prompt(text, history)
	local h = {
		nowrap = true,
		dobreak = false
	}
	if history then
		for i=1, #history do
			h[i] = history[i]
		end
	end
	local w, vh = term.getViewport()
	term.setCursor(1, vh)
	term.write("\27[47;30m")
	term.clearLine()
	term.write(string.format("%s %s: ", self:spinner(), text))
	local rtv = self:termread(h)--term.read(h)
	if rtv then
		rtv = rtv:gsub("\n$", "")
	end
	self:clear()
	self:draw()
	return rtv
end

local function format_url(url)
	return string.format("%s://%s:%d/%s/%s", url.proto, url.host, url.port, url.hint, url.rsc)
end

function browser:internal_error(err, text)
	self.error_state = true
	if self.texterror then
		self.textlines = "Critial error! "..err.."\n"..string.rep("-", term.getViewport()).."\n"..text
		self.state = "text"
	else
		self.lines = {
			{type = "3", display = err}
		}
		for line in text:gmatch("[^\n]*") do
			table.insert(self.lines, {type="i", display = line})
		end
		self.state = "menu"
	end
end

local proto_checks = {
	gomt = {gopher.has_minitel, "Minitel", "Install Minitel and the mtv2 library"},
	gopher = {gopher.has_internet, "Internet", "Install an internet card or contact your server admin."},
	about = {function()return true end, "internal", "internal error"}
}

function browser:navigate(url, nopush)
	local err
	self.error_state = false
	self.textlines = ""
	if not nopush and self.url ~= "Home" then
		self:push_history({
			display = self.url,
			url = self.url_tbl and format_url(self.url_tbl),
			tbl = self.url_tbl,
			selected = self.selected,
			offset = self.offset
		})
	end
	if type(url) == "string" then
		if url:sub(1, 8) == "about://" then
			url = self:handle_internal(url)
			goto finished
		end
		url, err = gopher.parse_url(url)
		if not url then
			self:internal_error("URL parsing error", err)
			return
		end
	end
	do
		if url.proto == "about" then
			url = self:handle_internal("about://"..url.host)
			goto finished
		end
		local pc = proto_checks[url.proto]
		if not pc or not pc[1]() then
			self:internal_error("No connection ("..pc[2]..")", pc[3])
			return
		end
		self.loading = true
		local ready
		if self.loader then
			self.loader:kill()
		end
		self.loader = thread.create(function()
			xpcall(function()
				local res, file, buffer = gopher.req(url)
				if not res then
					self:internal_error("Connection error", file)
				elseif type(res) == "string" then
					self.state = "text"
					self.textlines = res
				elseif file then
					self.state = "text"
					self.textlines = "Download file "..format_url(url).."?\nCtrl-C to cancel."
					self.loading = false
					self:draw()
					local savepath = self:menubar_prompt("Save path")
					if savepath then
						self.loading = true
						self:download_file(res, buffer, savepath)
						self.loading = false
					end
				else
					self.state = "menu"
					self.lines = res
					self:recompute_links()
				end
				ready = true
				self.loader = nil
			end, self.err_handler)
		end)
		local last_draw = uptime()
		while not ready and not self.quit do
			if uptime()-last_draw > 0.2 then
				last_draw = uptime()
				self:draw_spinner()
				os.sleep(gopher.min_sleep)
			end
		end
	end
	::finished::
	self.url = format_url(url)
	self.url_tbl = url
	self.loading = false
	self.selected = 0
	self.offset = 0
	self.lcount = self:nlines()
	self:clear()
end

function browser:key_down(key, scancode)
	local w, h = term.getViewport()
	local vh = h-1
	local c = string.char(key)
	local skey = codes[scancode]
	if self.ignore_keys then return end
	if c == "q" then -- Quit
		self.quit = true
	elseif c == "g" then -- Goto
		local history = {}
		for i=1, #self.history do
			table.insert(history, self.history[#self.history-i+1].url)
		end
		local res = self:menubar_prompt("Enter URL", history)
		self:reset()
		if res then
			self:navigate(res)
		end
	elseif c == "h" then -- History
		--self.state = "history"
		self:navigate("about://history", self.url_tbl.proto == "about" and self.url_tbl.host == "history")
	elseif c == "b" then -- Bookmarks
		self:navigate("about://bookmarks")
	elseif c == "k" then
		local link = self.lines[self.selected]
		if link and link.type == settings.bookmark then
			-- Remove bookmark
			for i=1, #self.bookmarks do
				if self.bookmarks[i] == link.extra then
					table.remove(self.bookmarks, i)
					break
				end
			end
			self:save_bookmarks()
			self:navigate("about://bookmarks", true)
		elseif self.url_tbl.proto ~= "about" and self.url_tbl.host ~= "bookmarks" then
			-- Add bookmark
			local name = self:menubar_prompt("Bookmark Name", {})
			if name then
				table.insert(self.bookmarks, {name = name, url = self.url_tbl})
				self:save_bookmarks()
			end
		end
	elseif skey == "left" then -- Go back
		local hist_ent = self:pop_history()
		if hist_ent then
			if self.state == "text" and self.url ~= "Home" then
				self.state = "menu"
				self:nav_reset(hist_ent)
			else
				self:navigate(hist_ent.tbl, true)
				self:nav_reset(hist_ent)
			end
		end
	elseif skey == "pgdn" then
		self.offset = self.offset + vh
		--self.selected = 0
	elseif skey == "pgup" then
		self.offset = self.offset - vh
		--self.selected = 0
	end
	if (self.state == "text") then
		if skey == "up" then
			self.offset = self.offset - 1
		elseif skey == "down" then
			self.offset = self.offset + 1
		end
	elseif self.state == "menu" then
		if skey == "up" then
			for i=#self.links, 1, -1 do
				if self.links[i] < self.selected then
					self.selected = self.links[i]
					goto found
				end
			end
			self.selected = 0
			::found::
		elseif skey == "down" then
			for i=1, #self.links do
				if self.links[i] > self.selected then
					self.selected = self.links[i]
					goto found
				end
			end
			self.selected = self.links[#self.links] or 0
			::found::
		elseif skey == "right" or key == 13 then
			local link = self.lines[self.selected]
			local host = link.host
			local url, proto
			if not host then goto continue end
			proto = host:match("(.-)://")
			if proto then
				host = host:match("://(.+)")
			end
			url = {
				proto = proto or self.lines.proto or "gopher",
				host = host,
				port = link.port,
				rsc = link.rsc,
				hint = link.type
			}
			if link.type == "7" then
				draw_search(self.selected-self.offset, link.display, "", true, w)
				local query = self:termread {--term.read {
					nowrap = true,
					dobreak = false,
					#self.query > 0 and self.query or nil
				}
				if query then
					query = query:gsub("\n$", "")
					url.rsc = url.rsc.."\t"..query
					self.query = query
					self:navigate(url)
				end
			elseif link.type == settings.bookmark then
				self:navigate(link.extra.url, true)
			elseif link.type == settings.history then
				local e
				repeat
					e = self:pop_history()
					if e == link.extra then
						break
					end
				until not e
				self:navigate(e.tbl, true)
				self:nav_reset(e)
			else
				self:navigate(url)
			end
			::continue::
		end
	end
	self.selected = self.selected or 0
	if self.selected > 0 then
		local off_sel = self.selected-self.offset
		if off_sel <= 0 then
			self.offset = self.selected-1
		elseif off_sel > vh then
			self.offset = self.selected-vh
		end
	end
	if self.offset > self.lcount-vh then
		self.offset = self.lcount-vh
	end
	if self.offset < 0 then
		self.offset = 0
	end
end

function browser:scroll(x, y, amt)
	local w, h = term.getViewport()
	local vh = h-1
	self.offset = self.offset - amt
	if self.offset > self.lcount-vh then
		self.offset = self.lcount-vh
	end
	if self.offset < 0 then
		self.offset = 0
	end
end

function browser:touch(x, y)
	local ry = self.offset+y
	local line = self.lines[ry]
	if line and line.type and line.display then
		if x > 3 and x < 3+utf8.len(line.display) then
			
		end
	end
end

function browser:download_file(con, buffer, path)
	local of, err = io.open(path, "w")
	if not of then
		self:internal_error("Failed to write file", err)
	end
	of:write(buffer)
	while true do
		local c = con:read(4096)
		if not c then break end
		of:write(c)
	end
	of:close()
	con:close()
	self.textlines = self.textlines.."\nSaved!"
end

return browser