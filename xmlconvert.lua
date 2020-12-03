#!/bin/env lua
local lt = ('<'):byte()
local gt = ('>'):byte()
local quot = ('"'):byte()
local apos = ("'"):byte()
local slash = ('/'):byte()

local preconverted = {
	['template/plugins$'] = ""
		.. "local path_to_plugins = GAMESTATE:GetCurrentSong():GetSongDir()..'plugins/'\n"
		.. "local af = Def.ActorFrame {}\n"
		.. "for _, filename in ipairs(FILEMAN:GetDirListing(path_to_plugins)) do\n"
		.. "	if string.sub(filename, -4, -1) == '.lua' then\n"
		.. "		af[#af + 1] = loadfile(path_to_plugins..filename)()\n"
		.. "	end\n"
		.. "end\n"
		.. "return af\n",
	['/copy$'] = ""
		.. "-- TODO"
		.. "return Def.Actor {}",
	['/j0e$'] = ""
}

local helperfunctions = {
	{
		"POptions", ""
		.. "local POptions = {\n"
		.. "	GAMESTATE:GetPlayerState(0):GetPlayerOptions('ModsLevel_Song'),\n"
		.. "	GAMESTATE:GetPlayerState(1):GetPlayerOptions('ModsLevel_Song'),\n"
		.. "}\n"
	},
	{
		"ApplyModifiers", ""
		.. "local function ApplyModifiers(str, pn)\n"
		.. "	if pn then\n"
		.. "		POptions[pn]:FromString(str)\n"
		.. "	else\n"
		.. "		POptions[1]:FromString(str)\n"
		.. "		POptions[2]:FromString(str)\n"
		.. "	end\n"
		.. "end\n"
	},
	{
		"ApplyGameCommand", ""
		.. "local function ApplyGameCommand(str, pn)\n"
		.. "	local a, b = str:find('^%s*mod%s*,')\n"
		.. "	if a then\n"
		.. "		str = str:sub(b + 1)\n"
		.. "		if pn then\n"
		.. "			POptions[pn]:FromString(str)\n"
		.. "		else\n"
		.. "			POptions[1]:FromString(str)\n"
		.. "			POptions[2]:FromString(str)\n"
		.. "		end\n"
		.. "	else\n"
		.. "		GAMESTATE:ApplyGameCommand(str, pn)\n"
		.. "	end\n"
		.. "end\n"
	},
	{
		"ConvertNoteData", ""
		.. "local NoteDataTypes = {\n"
		.. "	TapNoteType_Tap = 1,\n"
		.. "	TapNoteType_Mine = 'M',\n"
		.. "	TapNoteSubType_Hold = 2,\n"
		.. "	TapNoteSubType_Roll = 4,\n"
		.. "}\n"
		.. "local function ConvertNoteData(notedata)\n"
		.. "	for i, v in ipairs(notedata) do\n"
		.. "		v[2] = v[2] - 1 -- zero-indexed columns\n"
		.. "		v[3] = NoteDataTypes[v[3]]\n"
		.. "	end\n"
		.. "	return notedata\n"
		.. "end\n"
	},
	{
		"GetJudgmentSprite", ""
		.. "-- Thanks to MrThatKid for this code\n"
		.. "local function GetJudgmentSprite(actor)\n"
		.. "	if actor.GetChildren then\n"
		.. "		for i = 1, actor:GetNumChildren() do\n"
		.. "			local child = GetJudgmentSprite(actor:GetChildAt(i))\n"
		.. "			if child then return child end\n"
		.. "		end\n"
		.. "	else\n"
		.. "		return string.find(tostring(actor), \"^Sprite\") and actor:GetTexture():GetPath() ~= \"\" and actor\n"
		.. "	end\n"
		.. "end\n"
	}
}

local lfs = require('lfs')

local convert, convertstring, stripwhitespace, nextTag, parseTag,
	escape_string, simplify_path, update_lua_code, parse_cmd,
	parseAttr, emit, indent, dedent

function convert(filename, filenamefromsong)
	local file = io.open(filename..'.xml', 'r')
	local xml = file:read('*a')
	file:close()
	local lua
	for k, v in pairs(preconverted) do
		if filename:find(k) then
			lua = v
			break
		end
	end
	local lua = lua or convertstring(xml, filename, filenamefromsong)
	local file = io.open(filename..'.lua', 'w')
	file:write(lua)
	file:close()
end

function convertstring(str, filename, filenamefromsong)
	local len = #str
	local cursor = 1
	local bytes = {}
	for i = 1, #str do
		bytes[#bytes + 1] = str:sub(i, i):byte()
	end
	local tags = {}
	local n = 1
	while cursor do
		tags[n], cursor = nextTag(str, cursor, bytes, len, filename)
		n = n + 1 
	end
	local state = {}
	local root = parseTag(tags, filename, state)
	return emit(root, filename, filenamefromsong, state)
end

function update_lua_code(code, state)
	code = code

	-- hidden to visible
	:gsub(':hidden%(0%)',':visible(true)')
	:gsub(':hidden%(1%)',':visible(false)')
	:gsub(':hidden(%b())',':visible(0==%1)')

	-- GetChildAt semantic changes
	:gsub(':GetChildAt(%b())',':GetChildAt(1 + %1)')

	if code:find('GAMESTATE:ApplyModifiers') then
		state.POptions = true
		state.ApplyModifiers = true
		code = code:gsub('GAMESTATE:ApplyModifiers', 'ApplyModifiers')
	end
	if code:find('GAMESTATE:ApplyGameCommand') then
		state.POptions = true
		state.ApplyGameCommand = true
		code = code:gsub('GAMESTATE:ApplyGameCommand', 'ApplyGameCommand')
	end
	if code:find('%S:GetChild%([\'"]Judgment[\'"]%)GetChild%([\'"][\'"]%):Load%(') then
		state.GetJudgmentSprite = true
		code = code:gsub(
			'(%S+:GetChild%([\'"]Judgment[\'"]%)):GetChild%([\'"][\'"]%):Load%(',
			'GetJudgmentSprite(%1):Load('
		)
	end
	if code:find('GetNoteData') then
		code=code:gsub('[^%[%]%(%),%{%}%s]+%b():GetNoteData%b()', function(expr)
			state.ConvertNoteData = true
			return'ConvertNoteData('..expr..')'
		end)
		-- P[1]:GetNoteData()
		:gsub('[^%[%]%(%),%{%}%s]+%b[]:GetNoteData%b()', function(expr)
			state.ConvertNoteData = true
			return'ConvertNoteData('..expr..')'
		end)
		-- P1:GetNoteData()
		:gsub('[^%[%]%(%),%{%}%s]+:GetNoteData%b()', function(expr)
			state.ConvertNoteData = true
			return'ConvertNoteData('..expr..')'
		end)
	end
	code = code
	-- Screenman sugar (solves simple cases)
	:gsub('SCREENMAN%s*([\'"(])', 'SCREENMAN:GetTopScreen():GetChild%1')
	
	code = code
	-- IsAwake function doesn't exist
	:gsub('%S+:IsAwake%(%)', 'true')
	:gsub('FUCK_EXE', 'true')
	:gsub('tonumber%(GAMESTATE:GetVersionDate%(%)%)%s*>=%s*%d%d%d%d%d%d%d%d','true')
	:gsub('tonumber%(GAMESTATE:GetVersionDate%(%)%)','99999999')
	:gsub('GAMESTATE:GetVersionDate%(%)','"99999999"')
	
	code = code
	-- propagate some constants in cases where it works
	:gsub('not%s+true', 'false')
	:gsub('%s=%s+true%s+and', ' =')
	:gsub('and%s+true%s+then', 'then')
	:gsub('and%s+true%s+do', 'do')
	:gsub('=%s+false%s+or', '=')
	:gsub('or%s+false%s+then', 'then')
	:gsub('or%s+false%s+do', 'do')
	
	-- Renamed functions
	:gsub(':effectdelay%(', ':effect_hold_at_full(')
	:gsub(':SetFarDist%(', ':fardistz(')
	:gsub(':GetSongTime%(', ':GetCurMusicSeconds(')

	-- Removed functions
	:gsub('GAMESTATE:HideStageText%b()', '')
	
	-- Mirin Template Specific:l
	:gsub('max_pn = 8','max_pn = 2')
	:gsub('beat == oldbeat', 'beat <= oldbeat')
	
	-- Ease Reader Specific:
	:gsub('if%s*not%s*string%.find%s*%(%s*string%.lower%s*%(%s*PREFSMAN:GetPreference%s*%(%s*\'VideoRenderers\'%s*%)%s*%)%s*,%s*\'opengl\'%s*%)%s*'
		..'or%s*string%.find%s*%(%s*string%.lower%s*%(%s*PREFSMAN:GetPreference%s*%(%s*\'VideoRenderers\'%s*%)%s*%)%s*,%s*\'d3d\'%s*%)%s*'
		..'and%s*string%.find%s*%(%s*string%.lower%s*%(%s*PREFSMAN:GetPreference%s*%(%s*\'VideoRenderers\'%s*%)%s*%)%s*,%s*\'opengl\'%s*%)%s*'
		..'and%s*string%.find%s*%(%s*string%.lower%s*%(%s*PREFSMAN:GetPreference%s*%(%s*\'VideoRenderers\'%s*%)%s*%)%s*,%s*\'d3d\'%)%s*'
		..'<%s*string%.find%s*%(%s*string%.lower%s*%(%s*PREFSMAN:GetPreference%s*%(%s*\'VideoRenderers\'%s*%)%s*%)%s*,%s*\'opengl\'%)%s*'
		..'then%s*SCREENMAN:SystemMessage%s*%(%s*\'.-\'%s*%)%s*;?%s*end', '')
	:gsub('Trace%s*%(%s*\'NVidia%s*graphics%s*driver%s*detected%.\'%s*%)%s*;?%s*'
		..'Trace%s*%(%s*\'AFT%s*multiplier%s*set%s*to%s*0%.9\'%s*%)', '')
	:gsub('nvidia%s*=%s*false(%s*)'
		..'alphamult%s*=%s*1%s*'
		..'if%s*.-%s*then%s*'
		..	'nvidia%s*=%s*true%s*'
		..	'alphamult%s*=%s*0.9%s*'
		..'end\t*\r?\n?\t*', 'nvidia = true%1alphamult = 0.9')

	-- other vendor funnies
	:gsub('string%.find%s*%(%s*string%.lower%s*%(%s*DISPLAY:GetVendor%s*%(%s*%)%s*%)%s*,%s*\'nvidia\'%s*%)', 'true')
	
	-- lua behavior changes
	:gsub("'\\([%[%]])'", "'%1'") -- puuro what
	:gsub("(%s)for(.-)in%s+([%w_]+)%s+do(%s)","%1for%2in ipairs(%3) do --[[PORTSM5: iteration algorithm not specified. pairs might be more appropriate here]] %4") -- legacy lua4.0 loops into pairs
	:gsub("(%s)for(.-)in%s+%(([%w_]+)%)%s+do(%s)","%1for%2in ipairs(%3) do --[[PORTSM5: iteration algorithm not specified. pairs might be more appropriate here]] %4") -- curse you speed star kanade
	-- cmd code
	:gsub(":cmd%(['\"](.-)['\"]%)",parse_cmd_inner) -- normal cmd
	:gsub("([^%[%]%(%),%{%}%s]+):cmd%(([%w_]+)%s*%.%.%s*','%s*%.%.%s*([%w_]+)%)", '%1[%2](%1, %3)') -- thanks, Venomous Firefly/lua/modhelpers line 34
	return code
end

function stripwhitespace(str)
	return str:match('%s*(.*)%s*')
end

function nextTag(str, cursor, bytes, len, filename)
	cursor = str:find('<', cursor, true)
	if not cursor then return nil end
	-- skip comments
	while str:sub(cursor, cursor + 3) == '<!--' do
		cursor = str:find('-->', cursor, true)
		if not cursor then
			print("WARNING: UNFINISHED XML COMMENT in '"..filename.."'")
			return nil
		end
		cursor = str:find('<', cursor, true)
		if not cursor then return nil end
	end
	local start = cursor
	-- skip strings
	local stringtype = nil
	while stringtype or bytes[cursor] ~= gt do
		cursor = cursor + 1
		assert(cursor <= len, "ERROR: UNFINISHED XML STRING in '"..filename.."'")
		if bytes[cursor] == stringtype then
			stringtype = nil
		elseif not stringtype then
			if (bytes[cursor] == quot or bytes[cursor] == apos) then
				stringtype = bytes[cursor]
			end
		end
	end
	local body
	if bytes[start + 1] == slash then
		body = {
			type = 'close',
			text = str:sub(start + 2, cursor - 1)
		}
	elseif bytes[cursor - 1] == slash then
		body = {
			type = 'contained',
			text = str:sub(start + 1, cursor - 2)
		}
	else
		body = {
			type = 'open',
			text = str:sub(start + 1, cursor - 1)
		}
	end
	cursor = cursor + 1
	return body, cursor
end

function parseTag(tags, filename, state, i, level)
	i = i or 1
	level = level or 0
	assert(tags[i], "WARNING: NOT SURE WHAT HAPPENED in '"..filename.."'")
	assert(tags[i].type ~= 'close', "WARNING: MISMATCHED XML TAG in '"..filename.."'")
	local tag = parseAttr(tags[i], state, level + 1)
	i = i + 1
	if tag.type == 'open' then
		tag.children = {}
		assert(tags[i], "WARNING: UNCLOSED XML TAG in '"..filename.."'")
		while tags[i].type ~= 'close' do
			local child, next, reported = parseTag(tags, filename, state, i, level + 1)
			table.insert(tag.children, child)
			if not tags[next] then
				if not reported then
					print("WARNING: UNCLOSED XML TAG in '"..filename.."'")
				end
				return tag, next, true
			end
			i = next
		end
		assert(parseAttr(tags[i], state).name == tag.name, "ERROR: MISMATCHED XML TAG in '"..filename.."'")
		i = i + 1
	end
	return tag, i
end

function escape_string(str)
	return '"'..str:gsub('\\', '\\\\'):gsub('"','\"'):gsub("\r","\\r"):gsub("\n", "\\n")..'"'
end

function simplify_path(path)
	return (path:gsub('//+','/')
		:gsub('[^/]+/%.%./', '')
		:gsub('%./',''))
end

local firstparamisstring = {
	luaeffect = true,
	horizalign = true,
	vertalign = true,
	effectclock = true,
	blend = true,
	ztestmode = true,
	cullmode = true,
	playcommand = true,
	queuecommand = true,
	queuemessage = true,
	settext = true,
}

function parse_cmd(str, state)
	if str:find('^%s*$') then
		return update_lua_code("function() end")
	else
		return update_lua_code("function(self)\n\tself"..parse_cmd_inner(str).."\nend", state)
	end
end

function parse_cmd_inner(str)
	local out = {}
	for cmd in str:gmatch('[^;]+') do
		local i = 0
		local firstparam = false
		if cmd:find('%S') then
			for item in cmd:gmatch('[^,]+') do
				if i == 0 then
					item = string.lower(item:sub(item:find('%S+')))
					table.insert(out, ":" .. item)
					table.insert(out, '(')
					if firstparamisstring[item] then
						firstparam = true
					end
				else
					if i ~= 1 then
						table.insert(out, ', ')
					end
					if i == 1 and firstparam then
						table.insert(out, escape_string(item))
					elseif item:sub(1, 1) == '#' then
						local count = 0
						for byte in item:gmatch('[a-fA-F0-9][a-fA-F0-9]') do
							if count ~= 0 then table.insert(out, ', ') end
							table.insert(out, tostring(tonumber(byte, 16)/255))
							count = count + 1
						end
						if count == 3 then
							table.insert(out, ', 1')
						end
					else
						table.insert(out, item)
					end
				end
				i = i + 1
			end
			table.insert(out, ')')
		end
	end
	return table.concat(out)
end

function process_attr(tag, key, val, state, level)
	local pre = val:sub(1, 1)
	if key == 'File' then
		table.insert(tag.attr, {
			key = key,
			val = val,
		})
	elseif pre == '%' or pre == '@' then
		local lastsemicolon = val:find(';%s*$')
		if lastsemicolon then -- Thabks daikyi
			val = val:sub(1, lastsemicolon-1)
		end
		table.insert(tag.attr, {
			key = key,
			val = dedent(update_lua_code(val:sub(2), state))
		})
	elseif key == 'Condition' then
		table.insert(tag.attr, {
			key = key,
			val = dedent(update_lua_code(val:sub(1), state))
		})
	elseif key:sub(-7, -1) == 'Command' then
		if key == 'Command' then key = 'OnCommand' end
		table.insert(tag.attr, {
			key = key,
			val = parse_cmd(val, state)
		})
	elseif key:sub(1, 5) == "Frame" or key:sub(1, 5) == "Delay" then
		tag.frames = tag.frames or {}
		local index = tonumber(key:sub(6)) + 1
		tag.frames[index] = tag.frames[index] or {}
		local index2 = key:sub(1, 1) == "F" and 1 or 2
		tag.frames[index][index2] = val
	elseif tonumber(val) then
		table.insert(tag.attr, {
			key = key,
			val = val
		})
	else
		table.insert(tag.attr, {
			key = key,
			val = escape_string(val)
		})
	end
end

function parseAttr(tag, state, level)
	local _, index = tag.text:find('%s')
	local out
	if not index then
		out = {name = tag.text, attr = {}, level = level}
	else
		out = {name = tag.text:sub(1, index - 1), attr = {}, level = level}
		for key, val in tag.text:sub(index + 1, -1):gmatch('%s*([^%s\'"]+)%s*=%s*"([^"]*)"') do
			local val = val:gsub('&quot.', '"'):gsub('&lt.', '<'):gsub('&gt.', '>'):gsub('&amp.', '&'):gsub('&apos.', '\'')
			process_attr(out, key, val, state, level)
		end
	end
	out.type = tag.type
	out.text = tag.text
	return out
end

function escape_key(key)
	if not key:find('^[A-Za-z0-9_]+$') then
		return '['..escape_string(key)..']'
	else
		return key
	end
end


function read_attributes_from_ini(tag, filename, filenamefromsong, filenamefromloader)
	local file = io.open(filename)
	local inicode = file:read('*a')
	file:close()
	for line in inicode:gmatch('[^\r\n]+') do
		local key, val = line:match("^([^ =]+)=(.*)$")
		if key and val then
			if key == "Texture"
			or key == "Meshes"
			or key == "Materials"
			or key == "Bones"
			or key == "File" then
				val = filenamefromloader .. val
			end
			process_attr(tag, key, val, state, level)
		end
	end
end

function emit(tag, filename, filenamefromsong, state, level, out)
	out = out or {}
	level = level or 0

	if level == 0 then
		for _, helper in ipairs(helperfunctions) do
			if state[helper[1]] then
				table.insert(out, helper[2])
			end
		end
		if tag.attr[1] and tag.attr[1].key == 'Condition' then
			-- attempt to inline outer Conditions
			local body = tag.attr[1].val
			if body:sub(1, 11) == '(function()' and body:sub(-6, -1) == 'end)()' then
				table.insert(out, dedent(body:sub(12, -7):gsub("return true%s*$", "")))
				table.insert(out, '\n')
				table.remove(tag.attr, 1)
			end
		end
	end
	local Type = tag.name
	local File = nil
	local Condition = nil
	for i = #tag.attr, 1, -1 do
		local attr = tag.attr[i]
		if attr.key == 'Type' then
			Type = attr.val:sub(2, -2)
			table.remove(tag.attr, i)
		elseif attr.key == 'File' then
			File = attr.val
			table.remove(tag.attr, i)
		elseif attr.key == 'Condition' then
			Condition = attr.val
			table.remove(tag.attr, i)
		elseif attr.key == "Font" or attr.key == "Text" then
			Type = "BitmapText"
		end
	end
	table.insert(out, ('\t'):rep(level))
	if level == 0 then
		table.insert(out, 'return ')
	end
	
	if Condition then
		table.insert(out, '(')
		table.insert(out, Condition)
		table.insert(out, ') and ')
	end

	if Type == "Aux" then
		Type = "Actor"
	elseif Type == "BitmapText" and File then
		table.insert(tag.attr, {
			key = "Font",
			val = '"'..File..'"',
		})
		File = nil
	elseif Type == "Polygon" then
		print('WARNING, found an ActorMultiVertex in "'..filename..'"')
		Type = "ActorMultiVertex" -- TODO
	end
	
	local needsDef = true
	local needsBody = true
	if File then
		if File:sub(1, 1) == "@" then
			print('Painful File shennanigans in "'..filename..'"')
			table.insert(tag.attr, {
				key = "File",
				val = File:sub(2),
			})
		else
			local path = filename:match(".+/") or './'
			local pathfromsong = filenamefromsong:match(".+/") or './'
			local FilePath = File:match(".+/") or './'
			local ext = File:match('%.[^%./]+$')
			if not ext then
				for item in lfs.dir(simplify_path(path..'/'..FilePath)) do
					if item == File and lfs.attributes(path..'/'..File).mode == "directory" then
						ext = ".xml"
					    File = File..'/default.xml'
					end
					local itemext = item:match('%.[^%./]+$')
					if itemext and itemext ~= '.lua' and File:match('[^/]*$')..itemext == item then
						ext = itemext
						File=File..ext
					end
				end
				if not ext then
					ext = '.png'
					print('could not determine extension '..File..'. because it is kind of likely that this is due to like dimensions or (doubleres) or something, we guess that it should be a sprite type')
				end
			end
			if ext == '.xml' then
				if File == 'spellcard.xml' or File == 'spellcards.xml' then
					table.insert(out, 'Def.Actor {\n')
					needsDef = false
				else
					table.insert(out,
					"assert(loadfile(GAMESTATE:GetCurrentSong():GetSongDir()..'"..
							simplify_path(pathfromsong..File:gsub('%.xml$','.lua'))..
							"'))()")
					if tag.attr[1] then
						table.insert(out, ' .. {\n')
						needsDef = false
					else
						needsBody = false
					end
				end
			else
				ext = ext:lower()
				if ext == '.png' or ext == '.jpg'
					or ext == '.bmp' or ext == '.gif'
					or ext == '.avi' or ext == '.mkv'
					or ext == '.mp4' or ext == '.mpeg'
					or ext == '.mpg' then
					Type = "Sprite"
					table.insert(tag.attr, {
						key = "Texture",
						val = escape_string(File),
					})
				elseif ext == '.txt' then
					Type = "Model"
					table.insert(tag.attr, {
						key = "Meshes",
						val = escape_string(File),
					})
					table.insert(tag.attr, {
						key = "Materials",
						val = escape_string(File),
					})
					table.insert(tag.attr, {
						key = "Bones",
						val = escape_string(File),
					})
				elseif ext == '.model' then
					Type = "Model"
					read_attributes_from_ini(tag, simplify_path(path..File), simplify_path(pathfromsong..File), FilePath)
				elseif ext == '.sprite' then
					Type = "Sprite"
					read_attributes_from_ini(tag, simplify_path(path..File), simplify_path(pathfromsong..File), FilePath)
				elseif ext == '.ogg' then
					Type = "Sound"
					table.insert(tag.attr, {
						key = "File",
						val = escape_string(File),
					})
				else
					error('Invalid filetype '..File..' in file '..filename)
				end
			end
		end
	end
	if needsBody then
		if level == 0 and not tag.attr[1] and (not tag.children or not tag.children[1]) then
			table.insert(out, 'Def.Actor {}')
		else
			if needsDef then
				table.insert(out, 'Def.'..Type..' {\n')
			end
			level = level + 1
			for _, attr in ipairs(tag.attr) do
				table.insert(out, ('\t'):rep(level))
				table.insert(out, escape_key(attr.key))
				table.insert(out, ' = ')
				table.insert(out, indent(attr.val, level - 1))
				table.insert(out, ',\n')
			end
			
			if tag.frames then
				table.insert(out, ('\t'):rep(level))
				table.insert(out, "Frames = {\n")
				level = level + 1
				for i, v in ipairs(tag.frames) do
					assert(v[1] and v[2], "unaligned frames")
					table.insert(out, ('\t'):rep(level))
					table.insert(out, "{Frame = ")
					table.insert(out, v[1])
					table.insert(out, ", Delay = ")
					table.insert(out, v[2])
					table.insert(out, "},\n")
				end
				level = level - 1
				table.insert(out, ('\t'):rep(level))
				table.insert(out, "},\n")
			end
			
			if Type == "ActorFrame" and tag.children and tag.children[1] then
				tag.children = tag.children[1].children
				for i = 1, #tag.children do
					tag.children[i].index = i
				end
				table.sort(tag.children, function(a, b)
					return a.name < b.name or a.name == b.name and a.index < b.index
				end)
				for _, child in ipairs(tag.children) do
					emit(child, filename, filenamefromsong, state, level, out)
					table.insert(out, ',\n')
				end
			end
			level = level - 1
			table.insert(out, ('\t'):rep(level))
			table.insert(out, '}')
		end
	end
	
	if Condition then
		table.insert(out, ' or Def.Actor {}')
	end
	
	if level == 0 then
		table.insert(out, '\n')
		return table.concat(out)
	end
end

function indent(str, n)
	local out = str:gsub('\n', '\n\t')
	if n and n ~= 0 then
		return indent(out, n - 1)
	else
		return out
	end
end

function dedent(str)
	str = str:gsub("%s+$","")
	str = str:gsub("^%s+","")
	local max = 20
	while not (str:find('\n[^\n\t]*$') or str:find('\n[^\n\t][^\n]*$') or not str:find('\n.') or max == 0) do
		str = str:gsub('\n[\t ]', '\n')
		max = max - 1
	end 
	if max == 0 then
		print("I HAD TROUBLE DEDENTING: "..str)
	end
	return str
end


local function convert_dir(path, pathfromsong)
	for file in lfs.dir(path) do
		if file:find('%.sm$') or file:find("%.ssc$") then
			pathfromsong = '.'
		end
	end
	for file in lfs.dir(path) do
		if file ~= "." and file ~= ".." then
			local child = path..'/'..file
			local attr = lfs.attributes(child)
			if attr.mode == "directory" then
				convert_dir(child, pathfromsong and pathfromsong..'/'..file)
			end
			if child:sub(-4, -1) == '.xml' then
				if pathfromsong then
					local childfromsong = pathfromsong..'/'..file
					print(simplify_path(child))
					convert(simplify_path(child:sub(1, -5)), simplify_path(childfromsong:sub(1, -5)))
				else
					print("WARNING: no .sm detected. Skipping file: "..child)
				end
			end
		end
	end
end

-- read args, or current dir
local input = {...}
input[1] = input[1] or '.'
for _, i in ipairs(input) do
	local out, err = pcall(function()
		local attr = lfs.attributes(i)
		if attr.mode == "directory" then
		    convert_dir(i)
		end
	end)
	if not out then print(err) end
end



