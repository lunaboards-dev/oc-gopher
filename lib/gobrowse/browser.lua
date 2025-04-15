local term = require("term")
local utils = require("gobrowse.util")
local gopher= require("libgopher")
local browser = {}

local function bit_depth()
	return term.gpu().getDepth()
end

function browser.new(brow)
	return setmetatable({
		browser = brow,
		url = "",
		history = {},
		current_state = "page"
	}, {__index=browser})
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
		rewrite_line(y, string.format("%s \27[%dm%s\27[0m", sym, dstr))
	end
end

local function draw_search(y, str, query, selected, w)
	draw_link(y, "🔍", str, selected, 35, w)
	term.write(": "..utils.uclamp(query, w-(term.getCursor()+1)))
end

function browser:draw_text()

end

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
	X = "XML"
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
		if not ent or not ent.type or ent.type == "+" then
			rewrite_line(i, "")
		elseif ent.type == "i" then
			rewrite_line(i, "   "..ent.display)
		elseif ent.type == "3" then
			rewrite_line(i, string.format("%s %s", etypes["3"], ent.display))
		elseif ent.type == "7" then
			draw_search(i, ent.display, self.query, sel, w)
		elseif cant_navigate[ent.type] then
			draw_link(i, etypes[ent.type], ent.display, sel, 31, w)
		else
			draw_link(i, etypes[ent.type], ent.display, sel, 36, w)
		end
	end
end

local spinner = {
	"|",
	"/",
	"-",
	"\\"
}

function browser:draw()
	if self.state == "menu" then
		self:draw_menu()
	elseif self.state == "text" then
		self:draw_text()
	elseif self.state == "history" then
		self:display_history()
	end
	local stat = "✔"
	if self.loading then
		stat = " "..spinner[math.floor(os.clock()*2)%4+1]
	end
	self:update_taskbar(stat)
end

function browser:key_down(key, scancode)
	local c = string.char(key)
	local skey = codes[scancode]

	if c == "q" then -- Quit
		self.quit = true
	elseif c == "g" then -- Goto
		local history = {}
		for i=1, #self.history do
			table.insert(history, self.history[#self.history-i+1].url)
		end
		local res = self:menubar_prompt("Enter URL", history)
		if res then
			self:navigate(res)
		end
	elseif c == "h" then -- History
		self.state = "history"
	elseif skey == "left" then -- Go back
		local hist_ent = self:pop_history()

	elseif skey == "right" or key == 13 then -- Follow link

	end
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
	local w, h = term.getViewport()
	term.setCursor(1, h)
	term.write("\27[47;30m")
	term.clearLine()
	term.write(text..": ")
	return term.read(h)
end

local function format_url(url)
	return string.format("%s://%s:%d/%s/%s", url.proto, url.host, url.port, url.hint, url.rsc)
end

function browser:internal_error(err, text)
	self.lines = {
		{type = "3", display = err}
	}
	for line in text:gmatch("[^\n]*") do
		table.insert(self.lines, {type="i", display = line})
	end
end

local proto_checks = {
	gomt = {gopher.has_minitel, "Minitel", "Install Minitel and the mtv2 library"},
	gopher = {gopher.has_internet, "Internet", "Install an internet card or contact your server admin."}
}

function browser:navigate(url, nopush)
	local err
	self.textlines = ""
	if not nopush then
		self:push_history({
			display = self.url,
			url = format_url(self.url_tbl),
			tbl = self.url_tbl
		})
	end
	if type(url) == "string" then
		url, err = gopher.parse_url(url)
		if not url then
			self:internal_error("URL parsing error", err)
			return
		end
	end
	local pc = proto_checks[url.proto]
	if not pc or not pc[1]() then
		self:internal_error("No connection ("..pc[2]..")", pc[3])
		return
	end
	self.loading = true
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
		local savepath = self:menubar_prompt("Save path")
		if savepath then
			self:download_file(res, buffer, savepath)
		end
	end
	self.loading = false
end

function browser:scroll(x, y, amt)

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