local M = {}

function M:peek(job)
	local start, cache = os.clock(), ya.file_cache(job)
	if not cache or self:preload() ~= 1 then
		return
	end	
	ya.sleep(math.max(0, 0.1 + start - os.clock()))
	ya.image_show(cache, job.area)
	-- ya.preview_widgets(job, {})
	ya.preview_widget(job, {})
end


function M:seek(job, units)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		local step = ya.clamp(-1, units, 1)
		-- ya.manager_emit("peek", { math.max(0, cx.active.preview.skip + step), only_if = job.file.url })
		ya.emit("peek", { math.max(0, cx.active.preview.skip + step), only_if = job.file.url })

	end
end

function M:preload(job)
    ya.dbg("Preloading audio-preview ***")
	if not job then
		return 1
	end
	
	local percentage = 5 + job.skip
	if percentage > 95 then
		ya.emit("peek", { 90, only_if = job.file.url, upper_bound = true })
		return 2
	end
	local cache = ya.file_cache(job)
	if not cache then
		return 1
	end

	local cha = fs.cha(cache)
	if cha and cha.len > 0 then
		return 1
	end

    -- generate image
	ya.err("Calling sox for: " .. tostring(job.file.url) .. ", cache: " .. tostring(cache))
	local child, code = Command("sox")
		:arg({tostring(job.file.url),
		     "-n", "trim", "0:00", "1:00",
		     "remix", "1",
		     "rate", "12k",
		     "spectrogram",
		     "-o", tostring(cache)})
		:spawn()

	if not child then
		ya.err("spawn `sox` command returns " .. tostring(code))
		return 0
	end

	local status = child:wait()
	return status and status.success and 1 or 2
end

-- ===== Linemode (audio metadata) =====

local DEFAULTS = {
	tool = "auto", -- "auto" | "ffprobe" | "soxi"
	duration = true,
	channels = true,
	samplerate = true,
	bitrate = true,
	size = true,
}

---@param secs number
---@return string
local function fmt_duration(secs)
	secs = math.floor(secs + 0.5)
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	local s = secs % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	else
		return string.format("%d:%02d", m, s)
	end
end

---@param hz number
---@return string
local function fmt_samplerate(hz)
	local int = math.floor(hz / 1000)
	local rem = math.floor(hz % 1000)
	if rem == 0 then
		return string.format("%dk", int)
	end
	return string.format("%dk%s", int, string.format("%03d", rem):gsub("0+$", ""))
end

---@param bps number
---@return string
local function fmt_bitrate(bps)
	return string.format("%dkb", math.floor(bps / 1000 + 0.5))
end

local UNITS = { "B", "K", "M", "G", "T", "P", "E" }

---@param value number
---@param digits integer
---@return number
local function round_sig(value, digits)
	if value == 0 then
		return 0
	end
	local mult = 10 ^ (math.floor(math.log(value, 10)) - digits + 1)
	return math.floor(value / mult + 0.5) * mult
end

---@param bytes number
---@return string
local function fmt_size(bytes)
	local i, value = 1, bytes
	while value >= 1024 and i < #UNITS do
		value = value / 1024
		i = i + 1
	end
	if i == 1 then
		return string.format("%dB", bytes)
	end

	local rounded = round_sig(value, 2)
	local s = rounded >= 10 and string.format("%.0f", rounded) or string.format("%.1f", rounded)
	s = s:gsub("%.", ",")
	if s:find(",", 1, true) then
		s = s:gsub("0+$", ""):gsub(",$", "")
	end
	return s .. UNITS[i]
end

-- Whether the bit rate is a meaningful "compression rate" (i.e. the codec is lossy)
---@param meta table
---@return boolean
local function is_lossy(meta)
	local codec = (meta.codec or ""):lower()
	return codec:find("mp3", 1, true) ~= nil
		or codec:find("mpeg", 1, true) ~= nil
		or codec:find("aac", 1, true) ~= nil
		or codec:find("vorbis", 1, true) ~= nil
		or codec:find("opus", 1, true) ~= nil
		or codec:find("wmav", 1, true) ~= nil
end

---@param path Path
---@return table?, Error?, boolean spawned
local function probe_ffprobe(path)
	local output, err = Command("ffprobe"):arg({
		"-v", "error",
		"-select_streams", "a:0",
		"-show_entries", "format=duration,bit_rate:stream=codec_name,channels,sample_rate",
		"-of", "json=c=1",
		tostring(path),
	}):output()
	if not output then
		return nil, err, false
	elseif not output.status.success then
		return nil, Err("%s", output.stderr ~= "" and output.stderr or "`ffprobe` failed"), true
	end

	local t = ya.json_decode(output.stdout)
	if type(t) ~= "table" then
		return nil, Err("Failed to decode `ffprobe` output"), true
	end

	local stream = t.streams and t.streams[1]
	if not stream then
		return nil, nil, true
	end

	local format = t.format or {}
	return {
		codec = stream.codec_name,
		channels = tonumber(stream.channels),
		samplerate = tonumber(stream.sample_rate),
		duration = tonumber(format.duration),
		bitrate = tonumber(format.bit_rate),
	}, nil, true
end

---@param path Path
---@return table?, Error?, boolean spawned
local function probe_soxi(path)
	local output, err = Command("soxi"):arg(tostring(path)):output()
	if not output then
		return nil, err, false
	elseif not output.status.success then
		return nil, Err("%s", output.stderr ~= "" and output.stderr or "`soxi` failed"), true
	end

	local meta = {}
	for line in output.stdout:gmatch("[^\r\n]+") do
		local key, value = line:match("^%s*(%a[%w ]-)%s*:%s*(.*)$")
		if key == "Channels" then
			meta.channels = tonumber(value)
		elseif key == "Sample Rate" then
			meta.samplerate = tonumber(value)
		elseif key == "Duration" then
			local h, m, s = value:match("(%d+):(%d+):([%d%.]+)")
			if h then
				meta.duration = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
			end
		elseif key == "Bit Rate" then
			local num, unit = value:match("^([%d%.]+)%s*(%a*)")
			local mult = ({ k = 1e3, K = 1e3, M = 1e6, m = 1e6 })[unit] or 1
			if num then
				meta.bitrate = tonumber(num) * mult
			end
		elseif key == "Sample Encoding" then
			meta.codec = value:find("MPEG", 1, true) and "mp3" or value
		end
	end

	return meta, nil, true
end

local get_tool = ya.sync(function(st) return st.tool end)

local set_tool = ya.sync(function(st, tool) st.tool = tool end)

local save = ya.sync(function(st, meta)
	st.meta = st.meta or {}
	for url, entry in pairs(meta) do
		st.meta[url] = entry
	end
	ui.render()
end)

local function setup(st, opts)
	opts = opts or {}
	local o = {}
	for k, v in pairs(DEFAULTS) do
		o[k] = v
	end
	for k, v in pairs(opts) do
		o[k] = v
	end

	st.meta = {}
	st.tool = o.tool ~= "auto" and o.tool or nil

	local function audio_parts(self)
		local meta = st.meta[tostring(self._file.url)]
		if not meta then
			return nil
		end

		local parts = {}
		if o.duration and meta.duration then
			parts[#parts + 1] = fmt_duration(meta.duration)
		end
		if o.channels and o.samplerate and meta.channels and meta.samplerate then
			parts[#parts + 1] = string.format("%dx%s", meta.channels, fmt_samplerate(meta.samplerate))
		elseif o.channels and meta.channels then
			parts[#parts + 1] = string.format("%dch", meta.channels)
		elseif o.samplerate and meta.samplerate then
			parts[#parts + 1] = fmt_samplerate(meta.samplerate)
		end
		if o.bitrate and meta.bitrate and is_lossy(meta) then
			parts[#parts + 1] = fmt_bitrate(meta.bitrate)
		end
		return parts
	end

	local function size_part(self)
		local size = self._file:size()
		if size then
			return fmt_size(size)
		end
		local folder = cx.active:history(self._file.url)
		return folder and tostring(#folder.files) or nil
	end

	-- Dedicated linemode, activated with `linemode = "audio"` in yazi.toml.
	-- Audio metadata comes first, the file size always comes last.
	Linemode.audio = function(self)
		local parts = audio_parts(self) or {}
		if o.size then
			local size = size_part(self)
			if size then
				parts[#parts + 1] = size
			end
		end
		return table.concat(parts, " ")
	end

	-- In any other linemode (mtime, btime, ...) append the audio metadata so it
	-- survives, for example, sorting by modified time. The size is skipped when
	-- the active linemode already renders it.
	Linemode:children_add(function(self)
		if not self._file.in_current or cx.active.pref.linemode == "audio" then
			return ""
		end

		local parts = audio_parts(self)
		if not parts then
			return ""
		end
		if o.size and cx.active.pref.linemode ~= "size" then
			local size = size_part(self)
			if size then
				parts[#parts + 1] = size
			end
		end
		return ui.Line { " ", table.concat(parts, " ") }
	end, 1400)
end

local function fetch(_, job)
	if #job.files == 0 then
		return true
	end

	local tool, meta, errors = get_tool(), {}, {}
	for i, file in ipairs(job.files) do
		local entry, err
		if i == 1 and tool ~= "ffprobe" and tool ~= "soxi" then
			local spawned
			entry, err, spawned = probe_ffprobe(file.path)
			if spawned then
				tool = "ffprobe"
			else
				entry, err, spawned = probe_soxi(file.path)
				tool = spawned and "soxi" or nil
			end
			if not tool then
				return true, Err("Neither `ffprobe` nor `soxi` is available")
			end
			set_tool(tool)
		elseif tool == "soxi" then
			entry, err = probe_soxi(file.path)
		else
			entry, err = probe_ffprobe(file.path)
		end

		if err then
			errors[#errors + 1] = tostring(err)
		end
		meta[tostring(file.url)] = entry
	end

	save(meta)
	if #errors > 0 then
		return true, Err("%s", errors[1])
	end
	return true
end

M.setup = setup
M.fetch = fetch

return M
