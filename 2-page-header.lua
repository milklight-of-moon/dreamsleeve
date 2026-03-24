-- page header 3.0 ultimate freakazoid

local _ = require("gettext")
local T = require("ffi/util").template
local UIManager = require("ui/uimanager")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local ReaderFooter = require("apps/reader/modules/readerfooter")
local ReaderView = require("apps/reader/modules/readerview")
local ReaderUI = require("apps/reader/readerui")
local Font = require("ui/font")
local BD = require("ui/bidi")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local TextWidget = require("ui/widget/textwidget")
local SpinWidget = require("ui/widget/spinwidget")
local DoubleSpinWidget = require("ui/widget/doublespinwidget")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local util = require("util")
local InputDialog = require("ui/widget/inputdialog")
local Presets = require("ui/presets")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local logger = require("logger")
local FontChooser = require("ui/widget/fontchooser")
local FontList = require("fontlist")
local Event = require("ui/event")
local cre = require("document/credocument"):engineInit()

local database_file = DataStorage:getDataDir() .. "/page_header_settings.lua"
local headerDB = LuaSettings:open(database_file)

local BOOK_SETTINGS_KEY = "BOOK_SETTINGS"

local DEFAULT_HEADER_SOURCE = "title"
local DEFAULT_BOOK_TOC_DEPTH = ""
local DEFAULT_CHAPTER_TOC_DEPTH = ""
local DEFAULT_HEADER_FACE = "NotoSerif-Regular.ttf"
local DEFAULT_FLEURON_COLOR_KEY = "100"
local DEFAULT_PAGE_NUMBER_FONT_FACE = "NotoSerif-Regular.ttf"
local DEFAULT_HEADER_STYLE = 0
local DEFAULT_DIVIDER_FONT_FACE = "NotoSans-Regular.ttf"
local DEFAULT_DIVIDER_GLYPH = ""
local DEFAULT_DIVIDER_MARGIN = -85
local DEFAULT_DIVIDER_PADDING = 0
local DEFAULT_DIVIDER_SIZE = 100
local DEFAULT_DIVIDER_PREVIEW_SIZE = 85
local DEFAULT_FLEURON_FONT_FACE = "NotoSans-Regular.ttf"
local DEFAULT_FLEURON_SIZE = 50
local DEFAULT_FLEURON_MARGIN = 10
local DEFAULT_FLEURON_HEIGHT = 15
local DEFAULT_FLEURON_LEFT = ""
local DEFAULT_FLEURON_RIGHT = ""
local DEFAULT_FLEURON_MIDDLE = ""
local DEFAULT_FLEURON_PREVIEW_SIZE = 85
local DEFAULT_CORNER_FONT_FACE = ""
local DEFAULT_CORNER_SIZE = 75
local DEFAULT_CORNER_PREVIEW_SIZE = 45
local DEFAULT_CORNER_MARGIN_X = 0
local DEFAULT_CORNER_MARGIN_Y = 0
local DEFAULT_CORNER_TL = ""
local DEFAULT_CORNER_TR = ""
local DEFAULT_CORNER_BL = ""
local DEFAULT_CORNER_BR = ""
local CRE_HEADER_DEFAULT_SIZE = 20
local DEFAULT_LETTER_SPACING = 0
local DEFAULT_TOP_HEADER_MARGIN = 0
local DEFAULT_BOTTOM_HEADER_MARGIN = 0

local function filenameFromPath(path)
    return path:match("([^/]+)$")
end

--------------------------------------------------------------------------
-- Utility: basic string helpers
--------------------------------------------------------------------------
local function trim(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$")
end

local function collapse_spaces(s)
    if not s then return "" end
    return s:gsub("%s+", " ")
end

local function normalize_str(s)
    if not s then return "" end
    s = tostring(s)
    s = s:lower()
    s = trim(s)
    s = collapse_spaces(s)
    return s
end

--------------------------------------------------------------------------
-- Deterministic hash (DJB2-like) -> returns 8-char hex string
--------------------------------------------------------------------------
local function hash_string_to_hex(s)
    s = s or ""
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 4294967296 -- keep 32-bit
    end
    return string.format("%08x", h)
end

--------------------------------------------------------------------------
-- Book identifier: prefer metadata (title + author), fallback to filepath,
-- final fallback to 'unknown_book'. Hash the identifier for compact keys.
--------------------------------------------------------------------------
local function getBookDocProps(ctx)
    return ctx
       and ctx.ui
       and ctx.ui.doc_settings
       and ctx.ui.doc_settings.data
       and ctx.ui.doc_settings.data.doc_props
end


local function getBookMeta(ctx)
    local dp = getBookDocProps(ctx) or {}
    return {
       -- uuid   = dp.identifiers,
        title  = dp.display_title or dp.title or dp.name,
        author = dp.author or dp.authors,
    }
end

local function getBookMetaKey(ctx)
    local dp = getBookDocProps(ctx)
    if not dp then return nil end

    if dp.identifiers and dp.identifiers ~= "" then
	--logger.info("getBookMetaKey: using UUID", tostring(dp.identifiers))
        return hash_string_to_hex(dp.identifiers)
    end
	--logger.info("getBookMetaKey: UUID missing, using title+author", tostring(dp.title), tostring(author) )
    return hash_string_to_hex(
        normalize_str((dp.display_title or dp.title or "") ..
        "|" ..
        (dp.author or dp.authors or ""))
    )
end

--------------------------------------------------------------------------
-- BOOK_SETTINGS helpers: read/save single mapping
--------------------------------------------------------------------------
local function readAllBookSettings()
    return headerDB:readSetting(BOOK_SETTINGS_KEY) or {}
end

local function writeAllBookSettings(tbl)
    headerDB:saveSetting(BOOK_SETTINGS_KEY, tbl)
end

local function getBookSettings(book_id)
    local all = readAllBookSettings()
    local entry = all[book_id]
    if not entry then return {} end

    -- backward compatibility: old flat tables
    if entry.settings then
        return entry.settings
    end

    return entry
end

local function saveBookSetting(book_id, key, value)
    local all = readAllBookSettings()
    all[book_id] = all[book_id] or {}
    all[book_id][key] = value
    writeAllBookSettings(all)
end

local function setBookSettings(book_id, settings_table, ctx)
    local all = readAllBookSettings()

    local meta = nil
    if ctx then
        meta = getBookMeta(ctx)
    elseif all[book_id] and all[book_id].meta then
        meta = all[book_id].meta
    end

    all[book_id] = {
        meta = meta,
        settings = settings_table or {},
    }

    writeAllBookSettings(all)
end

-- read-and-apply defaults
local function onFirstOpening(book_id, ctx)
    local all = readAllBookSettings()
    if all[book_id] and next(all[book_id]) then
        return
    end
	
-- Default values
local DEFAULTS = {
	book_header_source	  = DEFAULT_HEADER_SOURCE,
	book_toc_depth		  = DEFAULT_BOOK_TOC_DEPTH,
	chapter_toc_depth	  = DEFAULT_TOC_DEPTH,
    font_size             = CRE_HEADER_DEFAULT_SIZE,
	header_style		  = DEFAULT_HEADER_STYLE,
    top_header_margin     = DEFAULT_TOP_HEADER_MARGIN,
    bottom_header_margin  = DEFAULT_BOTTOM_HEADER_MARGIN,
    letter_spacing        = DEFAULT_LETTER_SPACING,
    font_face             = DEFAULT_HEADER_FACE,
	page_number_font_face = DEFAULT_PAGE_NUMBER_FONT_FACE,
    divider_font_face     = DEFAULT_DIVIDER_FONT_FACE,
    divider_glyph         = DEFAULT_DIVIDER_GLYPH,
	divider_size          = DEFAULT_DIVIDER_SIZE,
	divider_margin        = DEFAULT_DIVIDER_MARGIN,
	divider_padding       = DEFAULT_DIVIDER_PADDING,
	divider_preview_size  = DEFAULT_DIVIDER_PREVIEW_SIZE,
	fleuron_font_face     = DEFAULT_FLEURON_FONT_FACE,
	fleuron_color 	 	  = DEFAULT_FLEURON_COLOR_KEY,
	fleuron_size          = DEFAULT_FLEURON_SIZE,
	fleuron_margin        = DEFAULT_FLEURON_MARGIN,
	fleuron_height		  = DEFAULT_FLEURON_HEIGHT,
	fleuron_left		  = DEFAULT_FLEURON_LEFT,
	fleuron_right		  = DEFAULT_FLEURON_RIGHT,
	fleuron_middle		  = DEFAULT_FLEURON_MIDDLE,
	fleuron_preview_size  = DEFAULT_FLEURON_PREVIEW_SIZE,
	corner_size			  = DEFAULT_CORNER_SIZE,
	corner_preview_size   = DEFAULT_CORNER_PREVIEW_SIZE,
	corner_margin_x 	  = DEFAULT_CORNER_MARGIN_X,
	corner_margin_y		  = DEFAULT_CORNER_MARGIN_Y,
	corner_tl			  = DEFAULT_CORNER_TL,
	corner_tr			  = DEFAULT_CORNER_TR,
	corner_bl			  = DEFAILT_CORNER_BL,
	corner_br			  = DEFAULT_CORNER_BR,
	book_margins_to_preset = true,
    two_column_mode       = false,
	hide_title            = false,
    hide_page_number      = false,
    page_bottom_center    = false,
    alternate_page_align  = true,
	align_title_side 	  = false,
	align_title_page 	  = false,
	hide_chapter_word	  = false,
	titlepage_to_cover	  = false,
	childchapter_page	  = false,
	divider_flip		  = false,
}

local candidate = {}
for key, default_value in pairs(DEFAULTS) do
    local setting_name = "default_" .. key

    if not headerDB:has(setting_name) then
        if type(default_value) == "boolean" then
            if default_value then
                headerDB:makeTrue(setting_name)
            else
                headerDB:makeFalse(setting_name)
            end
        else
            headerDB:saveSetting(setting_name, default_value)
        end
    end

    if type(default_value) == "boolean" then
        candidate[key] = headerDB:isTrue(setting_name)
    else
        candidate[key] = headerDB:readSetting(setting_name)
    end
end

all[book_id] = {
    meta = getBookMeta(ctx),
    settings = candidate,
}
writeAllBookSettings(all)

end

local function ensureBookSettings(reader)
    local book_id = getBookMetaKey(reader)
    if not book_id then return end

    local bs = getBookSettings(book_id)
    if not bs or next(bs) == nil then
        onFirstOpening(book_id, reader)
        bs = getBookSettings(book_id) or {}
        setBookSettings(book_id, bs)
    end

    local font_keys = {
        "font_face",
        "page_number_font_face",
        "divider_font_face",
        "fleuron_font_face",
        "corner_font_face"
    }

    local missing_fonts = {}

    for _, key in ipairs(font_keys) do
        local face = bs[key]
        if face then
            local f = Font:getFace(face, bs.font_size or 18)
            if not f then
                -- Track missing fonts (just filename, no path, unique)
                local fname = face:match("([^/\\]+)%.%w+$") or face
                if not missing_fonts[fname] then
                    missing_fonts[fname] = true
                end

                logger.warn("ensureBookSettings: missing font for key", key, "face:", face, "→ replacing with default")
                bs[key] = DEFAULT_HEADER_FACE
            end
        end
    end

    local missing_list = {}
    for fname in pairs(missing_fonts) do
        table.insert(missing_list, fname)
    end
    if #missing_list > 0 then
        UIManager:show(InfoMessage:new{
            text = T(_("Page header could not find fonts and replaced with default:\n\n %1"), table.concat(missing_list, ", ")),
            show_delay = 0.5,
            timeout = 10,
        })
    end

    setBookSettings(book_id, bs)
    return bs, book_id
end

-- UTF-8 letter spacing
local function utf8_spaced(text, spacing)
    spacing = tonumber(spacing) or 0
    if spacing <= 0 or not text or text == "" then
        return text
    end

    local nbsp = util.unicodeCodepointToUtf8(0x200A)  -- unicode hair space glyph
    local spacer = string.rep(nbsp, spacing)

    local chars = {}
    for c in text:gmatch("([%z\1-\127\194-\244][\128-\191]*)") do
        chars[#chars + 1] = c
    end

    return table.concat(chars, spacer)
end

local function getBookMargins(ctx)
    return ctx
       and ctx.ui
       and ctx.ui.doc_settings
       and ctx.ui.doc_settings.data
       and ctx.ui.doc_settings.data
end

local function readDocMargins(ctx)
    local dp = getBookMargins(ctx) or {}
    local top   = dp.copt_t_page_margin
    local bottom = dp.copt_b_page_margin
    local h      = dp.copt_h_page_margins -- may be nil or a table {left, right}

    local left, right
    if type(h) == "table" then
        left  = h[1]
        right = h[2]
    end

    return {
        top = tonumber(top),
        bottom = tonumber(bottom),
        left = tonumber(left),
        right = tonumber(right),
        raw_h = h,
    }
end

local lowercase_exceptions = {
    ["a"] = true, ["an"] = true, ["the"] = true,
    ["and"] = true, ["but"] = true, ["or"] = true,
    ["for"] = true, ["nor"] = true, ["on"] = true,
    ["at"] = true, ["to"] = true, ["from"] = true,
    ["by"] = true, ["of"] = true, ["in"] = true,
}

local function titlecase(str)
    str = string.gsub(str, "[\u{2066}\u{2067}\u{2068}\u{2069}]", "")
    str = string.gsub(str, "\u{00A0}", " ")

    local buf = {}
    local words = {}
    
    for word in string.gmatch(str, "%S+") do
        table.insert(words, word)
    end

    for i, word in ipairs(words) do
        local first = string.sub(word, 1, 1)
        local rest  = string.sub(word, 2)
        local lower_word = string.lower(word)

        local capitalized

        if i == 1 or i == #words then
            capitalized = string.upper(first) .. string.lower(rest)
        else
            if lowercase_exceptions[lower_word] then
                capitalized = lower_word
            else
                capitalized = string.upper(first) .. string.lower(rest)
            end
        end

        table.insert(buf, capitalized)
    end

    return table.concat(buf, " ")
end
--[[
local GLYPH_TABLE = {
    ["Vintage Decorative Signs 4.ttf"] = {
        "", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", 
        "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", 
        "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", 
        "@", 
		
		"A", "B", "C", "D", "E", "F", "G", "H", "I", 
        "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", 
        "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", 
        "^", "_", "`", "a", "b", 
		
		"e", "f", "g", "i", "j", 
        "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", 
        "u", "v", "w", "x", "y", "z", "{", "|", "}", "~", 
        
		"¡", "¢", "£", "¤", "¥", "¦", "§", "¨", "©", "ª", 
        "«", "¬", "®", "¯", "°", "±", "²", "³", 
		
		"Æ", "Ç", "È", "É", "Ê", "Ë", "Ì", "Í", "Î", "Ï", 
        "Ð", "Ñ", "Ò", "Ó", "Ô", "Õ", "Ö", "×", "Ø", "Ù", 
        "Ú", "Û", "Ü", "Ý", "Þ", "ß", "à", "á", "â", "ã", 
        "ä", "å", "æ", "ç", "è",
		
		"´", "µ", "¶", "·", "¸", "¹", "º", "»", 
        "¼", "½", "¾", "¿", "À", "Á", "Â", "Ã", "Ä", "Å", 
		
		"ō",
    },
}
--]]
local DIVIDER_GLYPH_TABLE = {
    ["Vintage Decorative Signs 4.ttf"] = {
        "", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", 
        "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", 
        "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", 
        "@", 
    },
}

local FLEURON_GLYPH_TABLE = {
    ["Vintage Decorative Signs 4.ttf"] = {
		"", "A", "B", "C", "D", "E", "F", "G", "H", "I", 
        "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", 
        "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", 
        "^", "_", "`", "a", "b", 
    },
}

local CROWN_GLYPH_TABLE = {
    ["Vintage Decorative Signs 4.ttf"] = {
		"", "e", "f", "g", "i", "j", 
        "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", 
        "u", "v", "w", "x", "y", "z", "{", "|", "}", "~", 
        
		"¡", "¢", "£", "¤", "¥", "¦", "§", "¨", "©", "ª", 
        "«", "¬", "®", "¯", "°", "±", "²", "³", 
    },
}

local TILES_GLYPH_TABLE = {
    ["Vintage Decorative Signs 4.ttf"] = {
		"", "ő", "Æ", "Ç", "È", "É", "Ê", "Ë", "Ì", "Í", "Î", "Ï", 
        "Ð", "Ñ", "Ò", "Ó", "Ô", "Õ", "Ö", "×", "Ø", "Ù", 
        "Ú", "Û", "Ü", "Ý", "Þ", "ß", "à", "á", "â", "ã", 
        "ä", "å", "æ", "ç", "è", "é",
    },
}

local CORNUCOPIA_GLYPH_TABLE = {
    ["Vintage Decorative Signs 4.ttf"] = {
		"", "´", "µ", "¶", "·", "¸", "¹", "º", "»", 
        "¼", "½", "¾", "¿", "À", "Á", "Â", "Ã", "Ä", "Å", 
		
		"Ŗ", "ŗ", "Ř", "ō",
    },
}

local CORNER_GLYPH_TABLE = {
    ["Vintage Decorative Signs 4.ttf"] = {
        "",  "ê", "ë", "ì", "í", "ï", 
        "ð", "ñ", "ò", "ó", "ô", "õ", "ö", "ø", "ù", "ú", 
        "û", "ü", "ý", "þ", "ÿ", "ā", "Ă", "ă", "Ą", "ą", 
        "Ć", "ć", "Ĉ", "Ċ", "ċ", "Č", "č", "Ď", "ď", "Đ", 
        "đ", "ē", "Ĕ", "ĕ", "Ė", "ė", "Ę", "ę", "Ě", "Ĝ", 
        "ĝ", "Ğ", "ğ", "Ġ", "ġ", "Ģ", "ģ", "ĥ", "Ħ", "ħ", 
        "Ĩ", "ĩ", "Ī", "ī", "Ĭ", "Į", "į", "İ", "ı", "Ĳ", 
        "ĳ", "Ĵ", "ĵ", "ķ", "ĸ", "Ĺ", "ĺ", "Ļ", "ļ", "Ľ", 
        "ľ", "ŀ", "Ł", "ł", "Ń", "ń", "Ņ", "ņ", "Ň",
    },
}

local DEFAULT_GLYPHS = {"", "◆", "◇", "•", "·", "*", "—", "-"}

local DECOR_COLORS = {
    { label = _("10 %"),    key = "10", 	value = Blitbuffer.gray(0.1) },
    { label = _("20 %"),    key = "20", 	value = Blitbuffer.gray(0.2) },
    { label = _("30 %"),    key = "30",		value = Blitbuffer.gray(0.3) },
    { label = _("40 %"),    key = "40",		value = Blitbuffer.gray(0.4) },
    { label = _("50 %"),    key = "50",		value = Blitbuffer.gray(0.5) },
    { label = _("60 %"),    key = "60",     value = Blitbuffer.gray(0.6) },
    { label = _("70 %"),    key = "70",     value = Blitbuffer.gray(0.7) },
    { label = _("80 %"),    key = "80",     value = Blitbuffer.gray(0.8) },
    { label = _("90 %"),    key = "90",     value = Blitbuffer.gray(0.9) },
    { label = _("100 %"),   key = "100",	value = Blitbuffer.COLOR_BLACK },
}

local DEFAULT_FLEURON_COLOR_KEY = "100"

local COLOR_KEY_TO_VALUE = {}
local COLOR_VALUE_TO_KEY = {}
for _, entry in ipairs(DECOR_COLORS) do
    COLOR_KEY_TO_VALUE[entry.key] = entry.value
    COLOR_VALUE_TO_KEY[entry.value] = entry.key
end

local HEADER_STYLE_NAMES = {
[0] = _("Original"),
[1] = _("Uppercase"),
[2] = _("Lowercase"),
[3] = _("Title case"),
}

--------------------------------------------------------------------------
-- Menu patching: ReaderFooter:addToMainMenu
--------------------------------------------------------------------------
local about_text = _([[
	 (\ 
	 \'\ 
	  \'\     __________  
	  / '|   ()_________)
	  \ '/    \ ~~~~~~~~ \
	    \       \ ~~~~~~   \
	    ==).      \__________\
	   (__)       ()__________)
			  
Reading the way grandma intended.

Page header is displayed in reflowable documents (epub etc). Default settings can be set via longpress on menu options, except for 'Font case' and 'Title candidates' options (per book only) and 'Save book margins to preset' (global default only). Presets can also be used to set a 'default' state.

The page header top and bottom margins are relative to the top and bottom book margins. Divider and fleurons margins are in turn relative to the page header.

Settings are saved into a separate file, page_header_settings.lua which can be found in Koreader root folder. Each book generates a key based on the book's sidecar UUID.

'Treat title pages as cover pages' is going to hide the page header on all chapter pages, displaying it on its subchapter pages of the highest level. 'Treat subchapters as normal pages' will hide the page header on the chapter page of the first level and display it for its subchapter pages.

For decorative options to work select the font provided, or use your own and edit the glyph tables in lua for glyphs to display in the menu.

Using a smallcaps font is highly recommended. A tutorial is available for making a SC font with FontForge. It's a semi-automated process that should take just a few minutes.
https://pastebin.com/Rm8PrbEk
]])
local orig_ReaderFooter_addToMainMenu = ReaderFooter.addToMainMenu
function ReaderFooter:addToMainMenu(menu_items)
    orig_ReaderFooter_addToMainMenu(self, menu_items)

    local statusBar = menu_items.status_bar
    if not statusBar then return end
    statusBar.sub_item_table = statusBar.sub_item_table or {}

	local reader = self or ui.reader
	if not reader then
		return
	end
	local book_id = getBookMetaKey(reader)
	--logger.warn("addtomainmenu book_id", tostring(book_id))

	local book_settings = getBookSettings(book_id) or {}
	--logger.warn("addtomainmenu book_settings keys", next(book_settings) ~= nil or false)
	
	
	local preset_keys = { 
	"book_header_source", "book_toc_depth", "max_toc_depth", "header_style",
	"font_face", "page_number_font_face", "font_size", "top_header_margin", "bottom_header_margin", "letter_spacing",
    "divider_font_face", "divider_glyph", "divider_margin", "divider_size", "divider_padding", "divider_preview_size", "divider_flip",
	"fleuron_font_face", "fleuron_size", "fleuron_margin", "fleuron_left", "fleuron_right", "fleuron_height", "fleuron_middle", "fleuron_preview_size", "fleuron_color", 
    "corner_font_face", "corner_font_size", "corner_preview_size", "corner_margin_x", "corner_margin_y", "corner_tl", "corner_tr", "corner_bl", "corner_br",
	"two_column_mode", "hide_title", "hide_page_number", "page_bottom_center", "alternate_page_align",
	"align_title_side", "align_title_page", "hide_chapter_word", "titlepage_to_cover", "childchapter_page",
	"copt_t_page_margin", "copt_b_page_margin", "copt_h_page_margins",
    }

	self.page_header_preset_obj = {
    presets = headerDB:readSetting("page_header_presets", {}), -- saved presets
    cycle_index = headerDB:readSetting("page_header_presets_cycle_index") or 0,
    dispatcher_name = "load_page_header_preset",

    saveCycleIndex = function(this)
        headerDB:saveSetting("page_header_presets_cycle_index", this.cycle_index)
    end,

	buildPreset = function()
		local preset = {}
		-- existing simple keys copied
		for _, key in ipairs(preset_keys) do
			-- skip margin keys here, we'll set them explicitly below
			if key ~= "copt_t_page_margin" and key ~= "copt_b_page_margin" and key ~= "copt_h_page_margins" then
				preset[key] = book_settings[key]
			end
		end
		
		if headerDB:readSetting("book_margins_to_preset") == true then
			local docm = readDocMargins(self) -- pass 'self' or ctx appropriately
			preset.copt_t_page_margin = docm.top  --or book_settings.top_header_margin
			preset.copt_b_page_margin = docm.bottom --or book_settings.bottom_header_margin

			if docm.raw_h and type(docm.raw_h) == "table" then
				preset.copt_h_page_margins = { docm.raw_h[1], docm.raw_h[2] }
			end
		end

		return preset
	end,

	loadPreset = function(preset)
		-- 1) Update book_settings
		for _, key in ipairs(preset_keys) do
			if preset[key] ~= nil then
				book_settings[key] = preset[key]
			end
		end

		if headerDB:readSetting("book_margins_to_preset") == true then
			-- 2) Persist margins in Sidecar (metadata)
			local Sidecar = self.ui.doc_settings
			if Sidecar then
				Sidecar:saveSetting("copt_t_page_margin", preset.copt_t_page_margin)
				Sidecar:saveSetting("copt_b_page_margin", preset.copt_b_page_margin)
				Sidecar:saveSetting("copt_h_page_margins", preset.copt_h_page_margins)
				Sidecar:flush()
			end

			local doc = self.ui.document
			if doc and doc.configurable then
				doc.configurable.t_page_margin = preset.copt_t_page_margin
				doc.configurable.b_page_margin = preset.copt_b_page_margin
				doc.configurable.h_page_margins = preset.copt_h_page_margins
			end

			self.ui:handleEvent(Event:new("SetPageMargins", {
				preset.copt_h_page_margins[1],
				preset.copt_t_page_margin,
				preset.copt_h_page_margins[2],
				preset.copt_b_page_margin
			}))
		end

	end
	}
	local function buildFleuronCategory(glyph_list, path)

		local items = {}

		for _, glyph in ipairs(glyph_list) do
			table.insert(items, {
				text_func = function()

					local left  = book_settings.fleuron_left == glyph
					local right = book_settings.fleuron_right == glyph
					local middle = book_settings.fleuron_middle == glyph

					local suffix = ""
					if left and right and middle then
						suffix = " ‹›⋅"
					elseif left and right then
						suffix = " ‹›"
					elseif left then
						suffix = " ‹"
					elseif right then
						suffix = " ›"
					elseif middle then
						suffix = " ⋅"
					end

					return glyph .. suffix
				end,

				checked_func = function()
					return book_settings.fleuron_left == glyph
						or book_settings.fleuron_right == glyph
						or book_settings.fleuron_middle == glyph
				end,

				font_func = function(size)
					local current_size =
						book_settings.fleuron_preview_size or DEFAULT_FLEURON_PREVIEW_SIZE
					return Font:getFace(path, current_size)
				end,

				keep_menu_open = true,

				callback = function(touchmenu_instance)

					UIManager:show(MultiConfirmBox:new{
						text = T("Assign '%1' to middle, left or right glyph?", glyph),

						choice1_text = "Left",
						choice1_callback = function()
							book_settings.fleuron_left = glyph
							setBookSettings(book_id, book_settings)
							if touchmenu_instance then
								touchmenu_instance:updateItems()
							end
							UIManager:setDirty("all", "ui")
						end,

						choice2_text = "Right",
						choice2_callback = function()
							book_settings.fleuron_right = glyph
							setBookSettings(book_id, book_settings)
							if touchmenu_instance then
								touchmenu_instance:updateItems()
							end
							UIManager:setDirty("all", "ui")
						end,

						cancel_text = "Middle",
						cancel_callback = function()
							book_settings.fleuron_middle = glyph
							setBookSettings(book_id, book_settings)
							if touchmenu_instance then
								touchmenu_instance:updateItems()
							end
							UIManager:setDirty("all", "ui")
						end,
					})
				end,
			})
		end

		return items
	end
	
		-- Main Menu
		table.insert(statusBar.sub_item_table, {
				text = _("Page header"),
				sub_item_table = {
				{
					text_func = function() return _("Presets") end,
					keep_menu_open = true,
					sub_item_table_func = function()
						local items = Presets.genPresetMenuItemTable(
							self.page_header_preset_obj,
							_("Create new preset from current settings")
						)

						-- Add checkbox right after "Create new preset..."
						table.insert(items, 1, {
							text = _("Save book margins to preset"),
							checked_func = function()
								return headerDB:readSetting("book_margins_to_preset")
							end,
							callback = function()
								local value = not headerDB:readSetting("book_margins_to_preset")
								headerDB:saveSetting("book_margins_to_preset", value)
							end,
							keep_menu_open = true,
							--separator = true,
						})

						return items
					end,
					separator = true,
				},
			-- Display options (parent menu)
			{
				text = _("Display options"),
				keep_menu_open = true,

				sub_item_table_func = function()
					
				local items = {}
				table.insert(items, {
					text = _("Title candidates"),
					enabled_func = function()
						return not (book_settings.two_column_mode or false)
					end,
					sub_item_table_func = function()
					local sub_items = {}

					local page = self.ui.document:getCurrentPage()
					local ch_list = {}
					if self.ui.toc then
						ch_list = self.ui.toc:getFullTocTitleByPage(page) or {}
					end
					
					local book_title = ""
					local book_author = ""
					local book_language = ""
					if self.ui.doc_props then
						book_title = self.ui.doc_props.display_title or ""
						book_author = self.ui.doc_props.authors or ""
						book_language = self.ui.doc_props.language or ""
						if book_author:find("\n") then -- Show first author if multiple authors
							book_author =  T(_("%1"), util.splitToArray(book_author, "\n")[1])
						end
					end

					table.insert(sub_items, { text = _("Left title:"), enabled_func = function() return false end, })
					table.insert(sub_items, {
						text = _("Book title: ") .. book_title,
						checked_func = function()
							return (book_settings.book_header_source or "title") == "title"
						end,
						radio = true,
						callback = function()
							book_settings.book_header_source = "title"
							setBookSettings(book_id, book_settings)
							UIManager:setDirty("all", "ui")
						end,
					})

					table.insert(sub_items, {
						text = _("Book author: ") .. book_author,
						checked_func = function()
							return book_settings.book_header_source == "author"
						end,
						radio = true,
						callback = function()
							book_settings.book_header_source = "author"
							setBookSettings(book_id, book_settings)
							UIManager:setDirty("all", "ui")
						end,
					}) 

					-- TOC levels for BOOK header
					for depth = 1, max_toc_depth do
						if ch_list[depth] and ch_list[depth] ~= "" then
							local id = "toc:" .. depth

							table.insert(sub_items, {
								text = _("TOC ") .. depth .. ": " .. ch_list[depth],
								radio = true,

								checked_func = function()
									return book_settings.book_header_source == id
								end,

								callback = function()
									book_settings.book_header_source = id
									setBookSettings(book_id, book_settings)
									UIManager:setDirty("all", "ui")
								end,
							}) 
						end 
					end

					table.insert(sub_items, { text = _("Right title:"), enabled_func = function() return false end, })

					for depth = 1, max_toc_depth do
						if ch_list[depth] and ch_list[depth] ~= "" then
							table.insert(sub_items, {
								text = _("TOC ") .. depth .. ": " .. ch_list[depth],
								radio = true,
								checked_func = function()
									local curr = book_settings.chapter_toc_depth or max_toc_depth
									return curr == depth
								end,

								callback = function()
									book_settings.chapter_toc_depth = depth
									setBookSettings(book_id, book_settings)
									UIManager:setDirty("all", "ui")
								end,
							})
						end
					end

					return sub_items
				end, separator = true,
				})
				table.insert(items, {
				-- Two column mode
                text = _("Two column mode"),
                checked_func = function()
                    return book_settings.two_column_mode == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    
                    book_settings.two_column_mode = not (book_settings.two_column_mode or false)
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				hold_callback = function()
					local default_two_column_mode = headerDB:isTrue("default_two_column")
					UIManager:show(MultiConfirmBox:new{
						text = default_two_column_mode and
							_("Would you like to enable or disable two column mode by default?\n\nThe current default (★) is enabled.")
							or _("Would you like to enable or disable two column mode by default?\n\nThe current default (★) is disabled."),
						choice1_text_func = function()
							return default_two_column_mode and _("Enable (★)") or _("Enable")
						end,
						choice1_callback = function()
							headerDB:makeTrue("default_two_column")
						end,
						choice2_text_func = function()
							return default_two_column_mode and _("Disable") or _("Disable (★)")
						end,
						choice2_callback = function()
							headerDB:makeFalse("default_two_column")
						end,
					})
				end,
					separator = true,
				})
				-- Hige page title
				table.insert(items, {
				text = _("Hide title"),
                checked_func = function()
                    return book_settings.hide_title == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    book_settings.hide_title = not (book_settings.hide_title or false)
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				hold_callback = function()
					local default_hide_page_title = headerDB:isTrue("default_hide_title")
					UIManager:show(MultiConfirmBox:new{
						text = default_hide_page_title and
							_("Would you like to show or hide the title by default?\n\nThe current default (★) is hidden.")
							or _("Would you like to show or hide the title by default?\n\nThe current default (★) is shown."),
						choice1_text_func = function()
							return default_hide_page_title and _("Show") or _("Show (★)")
						end,
						choice1_callback = function()
							headerDB:makeFalse("default_hide_title")
						end,
						choice2_text_func = function()
							return default_hide_page_title and _("Hide (★)") or _("Hide")
						end,
						choice2_callback = function()
							headerDB:makeTrue("default_hide_title")
						end,
					})
				end,
				--separator = true,
				})
				-- Hide page number
				table.insert(items, {
				text = _("Hide page number"),
                checked_func = function()
                    return book_settings.hide_page_number == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    
                    book_settings.hide_page_number = not (book_settings.hide_page_number or false)
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				hold_callback = function()
					local default_hide_page = headerDB:isTrue("default_hide_page_number")
					UIManager:show(MultiConfirmBox:new{
						text = default_hide_page and
							_("Would you like to show or hide page number by default?\n\nThe current default (★) is hidden.")
							or _("Would you like to show or hide page number by default?\n\nThe current default (★) is shown."),
						choice1_text_func = function()
							return default_hide_page and _("Show") or _("Show (★)")
						end,
						choice1_callback = function()
							headerDB:makeFalse("default_hide_page_number")
						end,
						choice2_text_func = function()
							return default_hide_page and _("Hide (★)") or _("Hide")
						end,
						choice2_callback = function()
							headerDB:makeTrue("default_hide_page_number")
						end,
					})
				end,
				})
				-- Position page number at bottom center
				table.insert(items, {
                text = _("Bottom center page number"),
				enabled_func = function()
                    return not (book_settings.two_column_mode or false)
					and not (book_settings.align_title_side or false)
                end,
                checked_func = function()
                    
                    return book_settings.page_bottom_center == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    book_settings.page_bottom_center = not (book_settings.page_bottom_center or false)
                    setBookSettings(book_id, book_settings)
					UIManager:setDirty("all", "ui")
                end,
				hold_callback = function()
					local default_page_bottom = headerDB:isTrue("default_page_bottom_center")
					UIManager:show(MultiConfirmBox:new{
						text = default_page_bottom and
							_("Would you like to display the page number at the bottom by default?\n\nThe current default (★) is enabled.")
							or _("Would you like to display the page number at the bottom by default?\n\nThe current default (★) is disabled."),
						choice1_text_func = function()
							return default_page_bottom and _("Enable (★)") or _("Enable")
						end,
						choice1_callback = function()
							headerDB:makeTrue("default_page_bottom_center")
						end,
						choice2_text_func = function()
							return default_page_bottom and _("Disable") or _("Disable (★)")
						end,
						choice2_callback = function()
							headerDB:makeFalse("default_page_bottom_center")
						end,
					})
				end,
				})
				--[[
				-- Mirror page numbers
				table.insert(items, {
                text = _("Mirror page numbers"),
				enabled_func = function()
                    return not (book_settings.two_column_mode or false)
					and not (book_settings.page_bottom_center or false)
					and not (book_settings.hide_page_number or false)
                end,
                checked_func = function()
                    
                    return book_settings.alternate_page_align == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    
                    book_settings.alternate_page_align = not (book_settings.alternate_page_align or false)
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				hold_callback = function()
					headerDB:flush()
					local default_alternate_page = headerDB:isTrue("default_alternate_page_align")
					UIManager:show(MultiConfirmBox:new{
						text = default_alternate_page and
							_("Would you like to alternate pages by default?\n\nThe current default (★) is enabled.")
							or _("Would you like to alternate pages by default?\n\nThe current default (★) is disabled."),
						choice1_text_func = function()
							return default_alternate_page and _("Enable (★)") or _("Enable")
						end,
						choice1_callback = function()
							headerDB:makeTrue("default_alternate_page_align")
						end,
						choice2_text_func = function()
							return default_alternate_page and _("Disable") or _("Disable (★)")
						end,
						choice2_callback = function()
							headerDB:makeFalse("default_alternate_page_align")
						end,
					})
				end,
				})	
				--]]
				-- Mirror title to the side
				table.insert(items, {
                text = _("Mirror title to the side"),
				enabled_func = function()
                    return not (book_settings.two_column_mode or false)
					and not (book_settings.page_bottom_center or false)
					and not (book_settings.align_title_page or false)
                end,
                checked_func = function()
                    
                    return book_settings.align_title_side == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    
                    book_settings.align_title_side = not (book_settings.align_title_side or false)
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				hold_callback = function()
					local default_align_title_side = headerDB:isTrue("default_align_title_side")
					UIManager:show(MultiConfirmBox:new{
						text = default_align_title_side and
							_("Would you like to mirror title (side) by default?\n\nThe current default (★) is enabled.")
							or _("Would you like to mirror title (side) by default?\n\nThe current default (★) is disabled."),
						choice1_text_func = function()
							return default_align_title_side and _("Enable (★)") or _("Enable")
						end,
						choice1_callback = function()
							headerDB:makeTrue("default_align_title_side")
						end,
						choice2_text_func = function()
							return default_align_title_side and _("Disable") or _("Disable (★)")
						end,
						choice2_callback = function()
							headerDB:makeFalse("default_align_title_side")
						end,
					})
				end,
					--separator = true,
				})	
				-- Mirror title to the page number
				table.insert(items, {
                text = _("Mirror title to page number"),
				enabled_func = function()
                    return not (book_settings.two_column_mode or false)
					--and not (book_settings.page_bottom_center or false)
					and not (book_settings.align_title_side or false)
                end,
                checked_func = function()
                    
                    return book_settings.align_title_page == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    
                    book_settings.align_title_page = not (book_settings.align_title_page or false)
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				hold_callback = function()
					local default_align_title_page = headerDB:isTrue("default_align_title_page")
					UIManager:show(MultiConfirmBox:new{
						text = default_align_title_page and
							_("Would you like to mirror title (page number) by default?\n\nThe current default (★) is enabled.")
							or _("Would you like to mirror title (page number) by default?\n\nThe current default (★) is disabled."),
						choice1_text_func = function()
							return default_align_title_page and _("Enable (★)") or _("Enable")
						end,
						choice1_callback = function()
							headerDB:makeTrue("default_align_title_page")
						end,
						choice2_text_func = function()
							return default_align_title_page and _("Disable") or _("Disable (★)")
						end,
						choice2_callback = function()
							headerDB:makeFalse("default_align_title_page")
						end,
					})
				end,
					separator = true,
				})
				-- Hide chapter word
				table.insert(items, {
                text = _("Remove chapter prefix"),
				enabled_func = function()
                    return not (book_settings.two_column_mode or false)
                end,
                checked_func = function()
                    return book_settings.hide_chapter_word == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    book_settings.hide_chapter_word = not (book_settings.hide_chapter_word or false)
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				hold_callback = function()
					local default_hide_chapter_word = headerDB:isTrue("default_hide_chapter_word")
					UIManager:show(MultiConfirmBox:new{
						text = default_hide_chapter_word and
							_("Would you like to remove chapter prefix by default?\n\nThe current default (★) is enabled.")
							or _("Would you like to remove chapter prefix by default?\n\nThe current default (★) is disabled."),
						choice1_text_func = function()
							return default_hide_chapter_word and _("Enable (★)") or _("Enable")
						end,
						choice1_callback = function()
							headerDB:makeTrue("default_hide_chapter_word")
						end,
						choice2_text_func = function()
							return default_hide_chapter_word and _("Disable") or _("Disable (★)")
						end,
						choice2_callback = function()
							headerDB:makeFalse("default_hide_chapter_word")
						end,
					})
				end,
					--separator = true,
				})
				-- Treat title page as cover page
				table.insert(items, {
                text = _("Treat title pages as cover pages"),
				enabled_func = function()
                    return not (book_settings.two_column_mode or false)
                end,
                checked_func = function()
                    return book_settings.titlepage_to_cover == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    book_settings.titlepage_to_cover = not (book_settings.titlepage_to_cover or false)
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				hold_callback = function()
					local default_titlepage_to_cover = headerDB:isTrue("default_titlepage_to_cover")
					UIManager:show(MultiConfirmBox:new{
						text = default_titlepage_to_cover and
							_("Would you like to treat a title page as cover page default?\n\nThe current default (★) is enabled.")
							or _("Would you like to treat a title page as cover page by default?\n\nThe current default (★) is disabled."),
						choice1_text_func = function()
							return default_titlepage_to_cover and _("Enable (★)") or _("Enable")
						end,
						choice1_callback = function()
							headerDB:makeTrue("default_titlepage_to_cover")
						end,
						choice2_text_func = function()
							return default_titlepage_to_cover and _("Disable") or _("Disable (★)")
						end,
						choice2_callback = function()
							headerDB:makeFalse("default_titlepage_to_cover")
						end,
					})
				end,
					--separator = true,
				})
				-- Treat chapter children as regular pages
				table.insert(items, {
                text = _("Treat subchapters as normal pages"),
				enabled_func = function()
                    return not (book_settings.two_column_mode or false)
                end,
                checked_func = function()
                    return book_settings.childchapter_page == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    book_settings.childchapter_page = not (book_settings.childchapter_page or false)
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				hold_callback = function()
					local default_childchapter_page = headerDB:isTrue("default_childchapter_page")
					UIManager:show(MultiConfirmBox:new{
						text = default_childchapter_page and
							_("Would you like to treat chapter children as regular pages default?\n\nThe current default (★) is enabled.")
							or _("Would you like to treat chapter children as regular pages by default?\n\nThe current default (★) is disabled."),
						choice1_text_func = function()
							return default_childchapter_page and _("Enable (★)") or _("Enable")
						end,
						choice1_callback = function()
							headerDB:makeTrue("default_childchapter_page")
						end,
						choice2_text_func = function()
							return default_childchapter_page and _("Disable") or _("Disable (★)")
						end,
						choice2_callback = function()
							headerDB:makeFalse("default_childchapter_page")
						end,
					})
				end,
					separator = true,
				})
					return items
					end,
					--separator = true,
				},
				
				-- Divider and fleuron settings (parent menu)
				{
				text = _("Divider, fleurons & corners"),
				keep_menu_open = true,
				enabled_func = function()
                    return not (book_settings.two_column_mode or false)
                end,
				sub_item_table_func = function()
					
					local items = {}
					-- Divider font face
					table.insert(items, {
						text_func = function()
						
						local path = book_settings.divider_font_face
						local default_path = headerDB:readSetting("default_divider_font_face")
						local font_name = nil

						if path then
							for i, name in ipairs(cre.getFontFaces()) do
								if cre.getFontFaceFilenameAndFaceIndex(name) == path then
									font_name = name
									break
								end
							end
						end

						if not path then
							if default_path then
								for i, name in ipairs(cre.getFontFaces()) do
									if cre.getFontFaceFilenameAndFaceIndex(name) == default_path then
										font_name = T(_("Default unset (%1)"), name)
										break
									end
								end
							end
							font_name = font_name or _("not set")
						elseif default_path and path == default_path then
							font_name = T(_("Default (%1)"), font_name or _("not set"))
						end

						return T(_("Divider font: %1"), font_name or _("not set"))
					end,

					keep_menu_open = true,
					sub_item_table_func = function()
						local items = {}
						
						local default_path = headerDB:readSetting("default_divider_font_face")

						for i, name in ipairs(cre.getFontFaces()) do
							local path = cre.getFontFaceFilenameAndFaceIndex(name)
							if path then
								local display_name = name
								if default_path and path == default_path then
									display_name = name .. " ★"
								end

								table.insert(items, {
									text = display_name,
									radio = true,  -- mark as radio button
									checked_func = function()
										return book_settings.divider_font_face == path
									end,
									font_func = function(size)
										return Font:getFace(path, size)
									end,
									enabled_func = function()
										
										return book_settings.divider_font_face ~= path
									end,
									keep_menu_open = true,
									callback = function()
										
										book_settings.divider_font_face = path
										setBookSettings(book_id, book_settings)
										UIManager:setDirty("all", "ui")
									end,
								})
							end
						end

						return items
					end,
					hold_callback = function(touchmenu_instance)
					local current_font_path = book_settings.divider_font_face
					local current_font_name = _("not set")
					if current_font_path then
						for i, name in ipairs(cre.getFontFaces()) do
							if cre.getFontFaceFilenameAndFaceIndex(name) == current_font_path then
								current_font_name = name
								break
							end
						end
					end

					local default_font_path = headerDB:readSetting("default_divider_font_face")
					local default_font_name = _("not set")
					if default_font_path then
						for i, name in ipairs(cre.getFontFaces()) do
							if cre.getFontFaceFilenameAndFaceIndex(name) == default_font_path then
								default_font_name = name
								break
							end
						end
					end

					if current_font_path == default_font_path then
						UIManager:show(InfoMessage:new{
							text = T(_("Current divider font (%1) is already the default."), current_font_name),
							timeout = 2,
						})
						return
					end

					UIManager:show(ConfirmBox:new{
						text = T(_("Set current divider font (%1) as default?\n\nThe current default is %2."),
							current_font_name, default_font_name),
						ok_text = _("Yes"),
						cancel_text = _("Cancel"),
						ok_callback = function()
							if current_font_path then
								headerDB:saveSetting("default_divider_font_face", current_font_path)
								UIManager:show(InfoMessage:new{
									text = T(_("Default divider font set to: %1"), current_font_name),
									show_delay = 0.3,
									timeout = 2,
								})
								touchmenu_instance:updateItems()
								UIManager:setDirty("all", "ui")
							else
								UIManager:show(InfoMessage:new{
									text = _("No font selected to save as default."),
									timeout = 3,
								})
							end
						end,
					})
				end,

				-- separator = true,
				})
					-- Divider glyph
					table.insert(items, {
					text_func = function()
						
						local g = book_settings.divider_glyph or DEFAULT_DIVIDER_GLYPH
						return T(_("Divider glyph: %1"), g)
					end,

					keep_menu_open = true,
					sub_item_table_func = function()
						
						local items = {}
						local path = book_settings.divider_font_face
						local font_key = path and filenameFromPath(path)

						--local glyphs = GLYPH_TABLE[font_key] or DEFAULT_GLYPHS
						local divider_glyphs = DIVIDER_GLYPH_TABLE[font_key] or DEFAULT_GLYPHS
						local fleuron_glyphs = FLEURON_GLYPH_TABLE[font_key] or DEFAULT_GLYPHS
						local crown_glyphs = CROWN_GLYPH_TABLE[font_key] or DEFAULT_GLYPHS
						local cornucopia_glyphs = CORNUCOPIA_GLYPH_TABLE[font_key] or DEFAULT_GLYPHS
						local tiles_glyphs = TILES_GLYPH_TABLE[font_key] or DEFAULT_GLYPHS
						local div_preview_size = book_settings.divider_preview_size
							or headerDB:readSetting("default_divider_preview_size")
							or DEFAULT_DIVIDER_PREVIEW_SIZE
	
					-- First item: manual entry
					table.insert(items, {
						text = _("Enter divider glyph"),
						font_func = function(size)
							return Font:getFace(divider_font, size)
						end,
						enabled_func = function()
							return true
						end,
						callback = function()
							local dialog
							dialog = InputDialog:new{
								title = _("Enter divider glyph"),
								input = book_settings.divider_glyph or DEFAULT_DIVIDER_GLYPH,
								input_hint = _("Single character"),
								buttons = {
									{
										{
											text = _("Close"),
											id = "close",
											callback = function() UIManager:close(dialog) end,
										},
										{
											text = _("Set"),
											callback = function()
												local user_glyph = dialog:getInputText()
												if user_glyph then
													book_settings.divider_glyph = user_glyph
													setBookSettings(book_id, book_settings)
													UIManager:setDirty("all", "ui")
												end
											end,
										},
									},
								},
							}
							UIManager:show(dialog)
							dialog:onShowKeyboard()
						end,
						--separator = true,
					})
				-- Divider size and margin
					table.insert(items, {
					text_func = function()
					local div_size = book_settings.divider_size or DEFAULT_DIVIDER_SIZE
					local div_margin = book_settings.divider_margin or DEFAULT_DIVIDER_MARGIN
					return T(_("Divider size/margin: %1 / %2"), div_size, div_margin)
					end,
			--	help_text = _("test."),
				callback = function(touchmenu_instance)
					local current_div_size = book_settings.divider_size or DEFAULT_DIVIDER_SIZE
					local current_div_margin = book_settings.divider_margin or DEFAULT_DIVIDER_MARGIN
					local default_div_size = headerDB:readSetting("default_divider_size") or DEFAULT_DIVIDER_SIZE
					local default_div_margin = headerDB:readSetting("default_divider_margin") or DEFAULT_DIVIDER_MARGIN
						local margin_widget 
						margin_widget = DoubleSpinWidget:new{
							title_text = _("Size/Margin"),
							left_value = current_div_size,
							left_min = 0,
							left_max = 500,
							left_step = 1,
							left_hold_step = 10,
							left_text = _("Size"),
							right_value = current_div_margin,
							right_min = -5000,
							right_max = 5000,
							right_step = 1,
							right_hold_step = 10,
							right_text = _("Margin"),
							left_default = default_div_size,
							right_default = default_div_margin,
							default_text = T(_("Default values: %1 / %2"), default_div_size, default_div_margin),
							width_factor = 0.6,
							--info_text = _([[Negative values reduce the gap.]]),
							keep_shown_on_apply = true,
							callback = function(left_divsize, right_divmargin)
								book_settings.divider_size = left_divsize
								book_settings.divider_margin = right_divmargin
								setBookSettings(book_id, book_settings)
								UIManager:setDirty("all", "ui")
							end,
							extra_text = _("Set as default"),
							extra_callback = function(left_divsize, right_divmargin)
								headerDB:saveSetting("default_divider_size", left_divsize)
								headerDB:saveSetting("default_divider_margin", right_divmargin)
								margin_widget.left_default  = left_divsize
								margin_widget.right_default = right_divmargin
								margin_widget.default_text  = T(_("Default values: %1 / %2"), left_divsize, right_divmargin)
								margin_widget:update()
								UIManager:setDirty("all", "ui")
							end,
						}
						UIManager:show(margin_widget)
					end,
					})
				-- Divider padding
				table.insert(items, {
				text_func = function()
					local div_padding = book_settings.divider_padding or DEFAULT_DIVIDER_PADDING
					return T(_("Divider padding: %1"), div_padding)
				end,
				keep_menu_open = false,
                callback = function(touchmenu_instance)
					local current_div_padding = book_settings.divider_padding or DEFAULT_DIVIDER_PADDING
					local default_div_padding = headerDB:readSetting("default_divider_padding") or DEFAULT_DIVIDER_PADDING
                    local spin_widget 
					spin_widget = SpinWidget:new{
                        title_text = _("Divider Padding"),
                        value = current_div_padding,
						default_value = default_div_padding,
                        value_min = -500,
                        value_max = 500,   
                        value_step = 1,
						value_hold_step = 5,
						--info_text = _([[Preview size in the fleuron glyph menu.]]),
                        keep_shown_on_apply = true,
                        callback = function(dividerpadding)
                            if dividerpadding.value ~= nil then
                                book_settings.divider_padding = dividerpadding.value
                                setBookSettings(book_id, book_settings)
								touchmenu_instance:updateItems()
								UIManager:setDirty("all", "ui")
                            end
                        end,
						extra_text = _("Set as default"),
						extra_callback = function(dividerpadding)
							headerDB:saveSetting("default_divider_padding", dividerpadding.value)
							spin_widget.default_value  = dividerpadding.value
							spin_widget:update()
						end,
                    }
                    UIManager:show(spin_widget)
					end,
					--separator = true,
				})
				-- Divider preview size
				table.insert(items, {
				text_func = function()
					
					local div_preview_size = book_settings.divider_preview_size or DEFAULT_DIVIDER_PREVIEW_SIZE
					return T(_("Glyph preview size: %1"), div_preview_size)
				end,
				keep_menu_open = true,
                callback = function(touchmenu_instance)
                    
					local current_div_preview_size = book_settings.divider_preview_size or DEFAULT_DIVIDER_PREVIEW_SIZE
					local default_div_preview_size = headerDB:readSetting("default_divider_preview_size") or DEFAULT_DIVIDER_PREVIEW_SIZE
                    local spin_widget 
					spin_widget = SpinWidget:new{
                        title_text = _("Divider preview size"),
                        value = current_div_preview_size,
						default_value = default_div_preview_size,
                        value_min = 0,
                        value_max = 500,   
                        value_step = 1,
						value_hold_step = 5,
						--info_text = _([[Back out to refresh.]]),
                        keep_shown_on_apply = true,
                        callback = function(dividerpreviewsize)
                            if dividerpreviewsize.value ~= nil then
                                book_settings.divider_preview_size = dividerpreviewsize.value
                                setBookSettings(book_id, book_settings)
								touchmenu_instance:updateItems()
								UIManager:setDirty("all", "ui")
                            end
                        end,
						extra_text = _("Set as default"),
						extra_callback = function(dividerpreviewsize)
							headerDB:saveSetting("default_divider_preview_size", dividerpreviewsize.value)
							spin_widget.default_value  = dividerpreviewsize.value
							spin_widget:update()
						end,
                    }
                    UIManager:show(spin_widget)
					end,
					--separator = true,
				})
				-- Flip divider
				table.insert(items, {
                text = _("Flip"),
				enabled_func = function()
                    return not (book_settings.align_title_side or false)
					and not (book_settings.page_bottom_center and not book_settings.align_title_page)
					and not (not book_settings.page_bottom_center and book_settings.align_title_page)

                end,
                checked_func = function()
                    return book_settings.divider_flip == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    book_settings.divider_flip = not (book_settings.divider_flip or false)
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				hold_callback = function()
					local default_divider_flip = headerDB:isTrue("default_divider_flip")
					UIManager:show(MultiConfirmBox:new{
						text = default_divider_flip and
							_("Would you like to flip the divider by default?\n\nThe current default (★) is enabled.")
							or _("Would you like to flip the divider by default?\n\nThe current default (★) is disabled."),
						choice1_text_func = function()
							return default_divider_flip and _("Enable (★)") or _("Enable")
						end,
						choice1_callback = function()
							headerDB:makeTrue("default_divider_flip")
						end,
						choice2_text_func = function()
							return default_divider_flip and _("Disable") or _("Disable (★)")
						end,
						choice2_callback = function()
							headerDB:makeFalse("default_divider_flip")
						end,
					})
				end,
					separator = true,
				})
				table.insert(items, {
				text = "Dividers",
				sub_item_table = (function()

					local glyph_items = {}

					for _, glyph in ipairs(divider_glyphs) do
						table.insert(glyph_items, {
							text = glyph,
							radio = true,
							checked_func = function()
								return book_settings.divider_glyph == glyph
							end,
							font_func = function(size)
								local current_size = book_settings.divider_preview_size
									or DEFAULT_DIVIDER_PREVIEW_SIZE
								return Font:getFace(path, current_size)
							end,
							callback = function()
								book_settings.divider_glyph = glyph
								setBookSettings(book_id, book_settings)
								UIManager:setDirty("all", "ui")
							end,
						})
					end

					return glyph_items
				end)(),
			})
				table.insert(items, {
				text = "Fleurons",
				sub_item_table = (function()

					local glyph_items = {}

					for _, glyph in ipairs(fleuron_glyphs) do
						table.insert(glyph_items, {
							text = glyph,
							radio = true,
							checked_func = function()
								return book_settings.divider_glyph == glyph
							end,
							font_func = function(size)
								local current_size = book_settings.divider_preview_size
									or DEFAULT_DIVIDER_PREVIEW_SIZE
								return Font:getFace(path, current_size)
							end,
							callback = function()
								book_settings.divider_glyph = glyph
								setBookSettings(book_id, book_settings)
								UIManager:setDirty("all", "ui")
							end,
						})
					end

					return glyph_items
				end)(),
			})
				table.insert(items, {
				text = "Crowns",
				sub_item_table = (function()

					local glyph_items = {}

					for _, glyph in ipairs(crown_glyphs) do
						table.insert(glyph_items, {
							text = glyph,
							radio = true,
							checked_func = function()
								return book_settings.divider_glyph == glyph
							end,
							font_func = function(size)
								local current_size = book_settings.divider_preview_size
									or DEFAULT_DIVIDER_PREVIEW_SIZE
								return Font:getFace(path, current_size)
							end,
							callback = function()
								book_settings.divider_glyph = glyph
								setBookSettings(book_id, book_settings)
								UIManager:setDirty("all", "ui")
							end,
						})
					end

					return glyph_items
				end)(),
			})
				table.insert(items, {
				text = "Tiles",
				sub_item_table = (function()

					local glyph_items = {}

					for _, glyph in ipairs(tiles_glyphs) do
						table.insert(glyph_items, {
							text = glyph,
							radio = true,
							checked_func = function()
								return book_settings.divider_glyph == glyph
							end,
							font_func = function(size)
								local current_size = book_settings.divider_preview_size
									or DEFAULT_DIVIDER_PREVIEW_SIZE
								return Font:getFace(path, current_size)
							end,
							callback = function()
								book_settings.divider_glyph = glyph
								setBookSettings(book_id, book_settings)
								UIManager:setDirty("all", "ui")
							end,
						})
					end

					return glyph_items
				end)(),
			})
			table.insert(items, {
				text = "Cornucopia",
				sub_item_table = (function()
				
					local glyph_items = {}

					for _, glyph in ipairs(cornucopia_glyphs) do
						table.insert(glyph_items, {
							text = glyph,
							radio = true,
							checked_func = function()
								return book_settings.divider_glyph == glyph
							end,
							font_func = function(size)
								local current_size = book_settings.divider_preview_size
									or DEFAULT_DIVIDER_PREVIEW_SIZE
								return Font:getFace(path, current_size)
							end,
							callback = function()
								book_settings.divider_glyph = glyph
								setBookSettings(book_id, book_settings)
								UIManager:setDirty("all", "ui")
							end,
						})
					end

					return glyph_items
				end)(),
			})
				--[[
				for _, glyph in ipairs(glyphs) do
					table.insert(items, {
						text = glyph,
						radio = true,
						checked_func = function()
							return book_settings.divider_glyph == glyph
						end,
						font_func = function(size)
							local current_size = book_settings.divider_preview_size or DEFAULT_DIVIDER_PREVIEW_SIZE
							return Font:getFace(path, current_size)
						end,
						callback = function()
							
							book_settings.divider_glyph = glyph
							setBookSettings(book_id, book_settings)
							UIManager:setDirty("all", "ui")
						end,
					})
				end
				--]]
						return items
					end,
					hold_callback = function()
						

						local current_glyph = book_settings.divider_glyph or ""
						local default_glyph = headerDB:readSetting("default_divider_glyph") or ""

						local function glyphLabel(glyph)
							return glyph ~= "" and glyph or _("not set")
						end
						
						if current_glyph == default_glyph then
							UIManager:show(InfoMessage:new{
								text = T(_("Current divider glyph %1 is already the default."), current_glyph),
								timeout = 2,
							})
							return
						end
						
						UIManager:show(MultiConfirmBox:new{
							text = T(
								_("Set the current divider glyph %1 as the default?\n\nThe current default (★) is %2."),
								glyphLabel(current_glyph),
								glyphLabel(default_glyph)
							),

							choice1_text_func = function()
								return current_glyph == default_glyph
									and T(_("Set (★)"), glyphLabel(current_glyph))
									or  T(_("Set"), glyphLabel(current_glyph))
							end,
							choice1_callback = function()
								headerDB:saveSetting("default_divider_glyph", current_glyph)
							end,

							choice2_text_func = function()
								return default_glyph == ""
									and _("Clear (★)")
									or  _("Clear")
							end,
							choice2_callback = function()
								headerDB:saveSetting("default_divider_glyph", "")
							end,
						})
					end,
				separator = true,
				})
						-- Fleuron font face
						table.insert(items, {
						text_func = function()
						
						local path = book_settings.fleuron_font_face
						local default_path = headerDB:readSetting("default_fleuron_font_face")
						local font_name = nil

						if path then
							for i, name in ipairs(cre.getFontFaces()) do
								if cre.getFontFaceFilenameAndFaceIndex(name) == path then
									font_name = name
									break
								end
							end
						end

						if not path then
							if default_path then
								for i, name in ipairs(cre.getFontFaces()) do
									if cre.getFontFaceFilenameAndFaceIndex(name) == default_path then
										font_name = T(_("Default unset (%1)"), name)
										break
									end
								end
							end
							font_name = font_name or _("not set")
						elseif default_path and path == default_path then
							font_name = T(_("Default (%1)"), font_name or _("not set"))
						end

						return T(_("Fleuron font: %1"), font_name or _("not set"))
					end,

					keep_menu_open = true,
					sub_item_table_func = function()
						local items = {}
						
						local default_path = headerDB:readSetting("default_fleuron_font_face")

						for i, name in ipairs(cre.getFontFaces()) do
							local path = cre.getFontFaceFilenameAndFaceIndex(name)
							if path then
								local display_name = name
								if default_path and path == default_path then
									display_name = name .. " ★"
								end

								table.insert(items, {
									text = display_name,
									radio = true,  -- mark as radio button
									checked_func = function()
										return book_settings.fleuron_font_face == path
									end,
									font_func = function(size)
										return Font:getFace(path, size)
									end,
									enabled_func = function()
										
										return book_settings.fleuron_font_face ~= path
									end,
									keep_menu_open = true,
									callback = function()
										
										book_settings.fleuron_font_face = path
										setBookSettings(book_id, book_settings)
										UIManager:setDirty("all", "ui")
									end,
								})
							end
						end

						return items
					end,
					hold_callback = function(touchmenu_instance)
					local current_font_path = book_settings.fleuron_font_face
					local current_font_name = _("not set")
					if current_font_path then
						for i, name in ipairs(cre.getFontFaces()) do
							if cre.getFontFaceFilenameAndFaceIndex(name) == current_font_path then
								current_font_name = name
								break
							end
						end
					end

					local default_font_path = headerDB:readSetting("default_fleuron_font_face")
					local default_font_name = _("not set")
					if default_font_path then
						for i, name in ipairs(cre.getFontFaces()) do
							if cre.getFontFaceFilenameAndFaceIndex(name) == default_font_path then
								default_font_name = name
								break
							end
						end
					end

					if current_font_path == default_font_path then
						UIManager:show(InfoMessage:new{
							text = T(_("Current fleuron font (%1) is already the default."), current_font_name),
							timeout = 2,
						})
						return
					end

					UIManager:show(ConfirmBox:new{
						text = T(_("Set current fleuron font (%1) as default?\n\nThe current default is %2."),
							current_font_name, default_font_name),
						ok_text = _("Yes"),
						cancel_text = _("Cancel"),
						ok_callback = function()
							if current_font_path then
								headerDB:saveSetting("default_fleuron_font_face", current_font_path)
								UIManager:show(InfoMessage:new{
									text = T(_("Default fleuron font set to: %1"), current_font_name),
									show_delay = 0.3,
									timeout = 2,
								})
								touchmenu_instance:updateItems()
								UIManager:setDirty("all", "ui")
							else
								UIManager:show(InfoMessage:new{
									text = _("No font selected to save as default."),
									timeout = 3,
								})
							end
						end,
					})
				end,
				-- separator = true,
				})
				-- Fleuron glyph
					table.insert(items, {
					text_func = function()
						
						local fle_left = book_settings.fleuron_left or DEFAULT_FLEURON_LEFT
						local fle_right = book_settings.fleuron_right or DEFAULT_FLEURON_RIGHT
						local fle_middle = book_settings.fleuron_middle or DEFAULT_FLEURON_MIDDLE
						return T(_("Fleuron glyphs: %1 %2 %3"), fle_middle, fle_left, fle_right)
					end,

					keep_menu_open = true,
					sub_item_table_func = function()
						
						local items = {}
						local path = book_settings.fleuron_font_face
						local font_key = path and filenameFromPath(path)

						--local glyphs = GLYPH_TABLE[font_key] or DEFAULT_GLYPHS
						local divider_glyphs = DIVIDER_GLYPH_TABLE[font_key] or DEFAULT_GLYPHS
						local fleuron_glyphs = FLEURON_GLYPH_TABLE[font_key] or DEFAULT_GLYPHS
						local crown_glyphs = CROWN_GLYPH_TABLE[font_key] or DEFAULT_GLYPHS
						local cornucopia_glyphs = CORNUCOPIA_GLYPH_TABLE[font_key] or DEFAULT_GLYPHS
						local tiles_glyphs = TILES_GLYPH_TABLE[font_key] or DEFAULT_GLYPHS
						local fle_preview_size = book_settings.fleuron_preview_size
							or headerDB:readSetting("default_fleuron_preview_size")
							or DEFAULT_FLEURON_PREVIEW_SIZE
	
					-- First item: manual entry
					table.insert(items, {
						text = _("Enter fleuron glyphs"),
						font_func = function(size)
							return Font:getFace(fleuron_font_face, size)
						end,
						enabled_func = function()
							return true
						end,
						callback = function()
							  local dialog
								dialog = MultiInputDialog:new{
									title = _("Fleuron glyphs"),
									fields = {
										{
											description = _("Left fleuron glyph"),
											text = book_settings.fleuron_left or DEFAULT_FLEURON_LEFT,
											hint = _("Single character"),
										},
										{
											description = _("Right fleuron glyph"),
											text = book_settings.fleuron_right or DEFAULT_FLEURON_RIGHT,
											hint = _("Single character"),
										},
										{
											description = _("Middle fleuron glyph"),
											text = book_settings.fleuron_middle or DEFAULT_FLEURON_MIDDLE,
											hint = _("Single character"),
										},
									},
									buttons = {
										{
											{
												text = _("Close"),
												id = "close",
												callback = function()
													UIManager:close(dialog)
												end,
											},
											{
												text = _("Set"),
												callback = function()
													local fields = dialog:getFields()
													--[[
													--take first UTF-8 char only
													local function first_char(s)
														if not s or s == "" then return "" end
														return s:match("^.[\128-\191]*")
													end
													--]]
													--book_settings.fleuron_left  = first_char(fields[1])
													book_settings.fleuron_left  = fields[1] or ""
													book_settings.fleuron_right = fields[2] or ""
													book_settings.fleuron_middle = fields[3] or ""
													setBookSettings(book_id, book_settings)
													if touchmenu_instance then
														touchmenu_instance:updateItems()
													end
													UIManager:setDirty("all", "ui")
												end,
											},
										},
									},
								}

								UIManager:show(dialog)
								dialog:onShowKeyboard()
							end,
						})
			-- Fleuron size and margin
			table.insert(items, {
               text_func = function()
				
				local fle_size = book_settings.fleuron_size or DEFAULT_FLEURON_SIZE
				local fle_margin = book_settings.fleuron_margin or DEFAULT_FLEURON_MARGIN
				return T(_("Fleuron size/padding: %1 / %2"), fle_size, fle_margin)
			end,
			keep_menu_open = false,
		--	help_text = _("test."),
			callback = function(touchmenu_instance)
				
				local current_fle_size = book_settings.fleuron_size or DEFAULT_FLEURON_SIZE
				local current_fle_margin = book_settings.fleuron_margin or DEFAULT_FLEURON_MARGIN
				local default_fle_size = headerDB:readSetting("default_fleuron_size") or DEFAULT_FLEURON_SIZE
				local default_fle_margin = headerDB:readSetting("default_fleuron_margin") or DEFAULT_FLEURON_MARGIN
                    local margin_widget 
					margin_widget = DoubleSpinWidget:new{
                        title_text = _("Size/Padding"),
                        left_value = current_fle_size,
						left_min = 0,
						left_max = 500,
						left_step = 1,
						left_hold_step = 5,
						left_text = _("Size"),
						right_value = current_fle_margin,
						right_min = -5000,
						right_max = 5000,
						right_step = 1,
						right_hold_step = 5,
						right_text = _("Padding"),
						left_default = default_fle_size,
						right_default = default_fle_margin,
						default_text = T(_("Default values: %1 / %2"), default_fle_size, default_fle_margin),
						width_factor = 0.6,
						--info_text = _([[Negative values reduce the gap.]]),
                        keep_shown_on_apply = true,
                        callback = function(left_flesize, right_flemargin)
							book_settings.fleuron_size = left_flesize
							book_settings.fleuron_margin = right_flemargin
							setBookSettings(book_id, book_settings)
							touchmenu_instance:updateItems()
							UIManager:setDirty("all", "ui")
						end,
						extra_text = _("Set as default"),
						extra_callback = function(left_flesize, right_flemargin)
							headerDB:saveSetting("default_fleuron_size", left_flesize)
							headerDB:saveSetting("default_fleuron_margin", right_flemargin)
							margin_widget.left_default  = left_flesize
							margin_widget.right_default = right_flemargin
							margin_widget.default_text  = T(_("Default values: %1 / %2"), left_flesize, right_flemargin)
							margin_widget:update()
							UIManager:setDirty("all", "ui")
						end,
					}
                    UIManager:show(margin_widget)
                end,
				})
				-- Fleuron height
				table.insert(items, {
				text_func = function()
					
					local fle_height = book_settings.fleuron_height or DEFAULT_FLEURON_HEIGHT
					return T(_("Middle fleuron margin: %1"), fle_height)
				end,
				keep_menu_open = true,
                callback = function(touchmenu_instance)
                    
					local current_fle_height = book_settings.fleuron_height or DEFAULT_FLEURON_HEIGHT
					local default_fle_height = headerDB:readSetting("default_fleuron_height") or DEFAULT_FLEURON_HEIGHT
                    local spin_widget 
					spin_widget = SpinWidget:new{
                        title_text = _("Middle fleuron margin"),
                        value = current_fle_height,
						default_value = default_fle_height,
                        value_min = -500,
                        value_max = 500,   
                        value_step = 1,
						value_hold_step = 5,
						--info_text = _([[Preview size in the fleuron glyph menu.]]),
                        keep_shown_on_apply = true,
                        callback = function(fleuronheight)
                            if fleuronheight.value ~= nil then
                                book_settings.fleuron_height = fleuronheight.value
                                setBookSettings(book_id, book_settings)
								touchmenu_instance:updateItems()
								UIManager:setDirty("all", "ui")
                            end
                        end,
						extra_text = _("Set as default"),
						extra_callback = function(fleuronheight)
							headerDB:saveSetting("default_fleuron_height", fleuronheight.value)
							spin_widget.default_value  = fleuronheight.value
							spin_widget:update()
						end,
                    }
                    UIManager:show(spin_widget)
					end,
					--separator = true,
				})
				-- Fleuron preview size
				table.insert(items, {
				text_func = function()
					
					local fle_preview_size = book_settings.fleuron_preview_size or DEFAULT_FLEURON_PREVIEW_SIZE
					return T(_("Glyph preview size: %1"), fle_preview_size)
				end,
				keep_menu_open = true,
                callback = function(touchmenu_instance)
                    
					local current_fle_preview_size = book_settings.fleuron_preview_size or DEFAULT_FLEURON_PREVIEW_SIZE
					local default_fle_preview_size = headerDB:readSetting("default_fleuron_preview_size") or DEFAULT_FLEURON_PREVIEW_SIZE
                    local spin_widget 
					spin_widget = SpinWidget:new{
                        title_text = _("Fleuron preview size"),
                        value = current_fle_preview_size,
						default_value = default_fle_preview_size,
                        value_min = 0,
                        value_max = 500,   
                        value_step = 1,
						value_hold_step = 5,
						--info_text = _([[Preview size in the fleuron glyph menu.]]),
                        keep_shown_on_apply = true,
                        callback = function(fleuronpreviewsize)
                            if fleuronpreviewsize.value ~= nil then
                                book_settings.fleuron_preview_size = fleuronpreviewsize.value
                                setBookSettings(book_id, book_settings)
								touchmenu_instance:updateItems()
								UIManager:setDirty("all", "ui")
                            end
                        end,
						extra_text = _("Set as default"),
						extra_callback = function(fleuronpreviewsize)
							headerDB:saveSetting("default_fleuron_preview_size", fleuronpreviewsize.value)
							spin_widget.default_value  = fleuronpreviewsize.value
							spin_widget:update()
						end,
                    }
                    UIManager:show(spin_widget)
					end,
					--separator = true,
				})
				table.insert(items, {
					text_func = function()
						local key = book_settings.fleuron_color or DEFAULT_FLEURON_COLOR_KEY
						for i, e in ipairs(DECOR_COLORS) do
							if e.key == key then
								return T(_("Opacity: %1"), e.label)
							end
						end
						return T(_("Opacity: %1"), _("Unknown"))
					end,
					sub_item_table = (function()
						local sub_items = {}
						for i, entry in ipairs(DECOR_COLORS) do
							table.insert(sub_items, {
								text = entry.label,
								radio = true,
								keep_menu_open = true,
								checked_func = function()
									local current_key = book_settings.fleuron_color or DEFAULT_FLEURON_COLOR_KEY
									return current_key == entry.key
								end,
								callback = function(touchmenu_instance)
									book_settings.fleuron_color = entry.key
									setBookSettings(book_id, book_settings)

									if touchmenu_instance then
										touchmenu_instance:updateItems()
									end
									UIManager:setDirty("all", "ui")
								end,
							})
						end
						return sub_items
					end)(),
					separator = true,
				})
				table.insert(items, {
					text = "Dividers",
					sub_item_table = buildFleuronCategory(divider_glyphs, path),
				})

				table.insert(items, {
					text = "Fleurons",
					sub_item_table = buildFleuronCategory(fleuron_glyphs, path),
				})

				table.insert(items, {
					text = "Crowns",
					sub_item_table = buildFleuronCategory(crown_glyphs, path),
				})

				table.insert(items, {
					text = "Tiles",
					sub_item_table = buildFleuronCategory(tiles_glyphs, path),
				})

				table.insert(items, {
					text = "Cornucopia",
					sub_item_table = buildFleuronCategory(cornucopia_glyphs, path),
				})
						return items
					end,
					hold_callback = function()
						

						local bl = book_settings.fleuron_left   or ""
						local bm = book_settings.fleuron_middle or ""
						local br = book_settings.fleuron_right  or ""

						local dl = headerDB:readSetting("default_fleuron_left")   or ""
						local dm = headerDB:readSetting("default_fleuron_middle") or ""
						local dr = headerDB:readSetting("default_fleuron_right")  or ""

						local function g(glyph)
							return glyph ~= "" and glyph or _("(None)")
						end

						local defaults_match =
							bl == dl and bm == dm and br == dr
						
						if defaults_match then
							UIManager:show(InfoMessage:new{
								text = T(_("Current fleurons: \n\nLeft: %1\nMiddle: %2\nRight: %3\n\nAre already the default."), g(bl), g(bm), g(br)),
								timeout = 3,
							})
							return
						end
						
						UIManager:show(MultiConfirmBox:new{
							text = T(
								_("Set the current fleurons as defaults?\n\nLeft:   %1\nMiddle: %2\nRight:  %3\n\nCurrent default (★):\nLeft:   %4\nMiddle: %5\nRight:  %6"),
								g(bl), g(bm), g(br),
								g(dl), g(dm), g(dr)
							),

							choice1_text_func = function()
								return defaults_match
									and _("Set (★)")
									or  _("Set")
							end,
							choice1_callback = function()
								headerDB:saveSetting("default_fleuron_left",   bl)
								headerDB:saveSetting("default_fleuron_middle", bm)
								headerDB:saveSetting("default_fleuron_right",  br)
							end,

							choice2_text_func = function()
								return defaults_match and _("Clear") or _("Clear")
							end,
							choice2_callback = function()
								headerDB:saveSetting("default_fleuron_left",   "")
								headerDB:saveSetting("default_fleuron_middle", "")
								headerDB:saveSetting("default_fleuron_right",  "")
							end,
						})
					end,
				separator = true,
				})
						-- Decorative corner font face
						table.insert(items, {
						text_func = function()
						
						local path = book_settings.corner_font_face
						local default_path = headerDB:readSetting("default_corner_font_face")
						local font_name = nil

						if path then
							for i, name in ipairs(cre.getFontFaces()) do
								if cre.getFontFaceFilenameAndFaceIndex(name) == path then
									font_name = name
									break
								end
							end
						end

						if not path then
							if default_path then
								for i, name in ipairs(cre.getFontFaces()) do
									if cre.getFontFaceFilenameAndFaceIndex(name) == default_path then
										font_name = T(_("Default unset (%1)"), name)
										break
									end
								end
							end
							font_name = font_name or _("not set")
						elseif default_path and path == default_path then
							font_name = T(_("Default (%1)"), font_name or _("not set"))
						end

						return T(_("Corner font: %1"), font_name or _("not set"))
					end,

					keep_menu_open = true,
					sub_item_table_func = function()
						local items = {}
						
						local default_path = headerDB:readSetting("default_corner_font_face")

						for i, name in ipairs(cre.getFontFaces()) do
							local path = cre.getFontFaceFilenameAndFaceIndex(name)
							if path then
								local display_name = name
								if default_path and path == default_path then
									display_name = name .. " ★"
								end

								table.insert(items, {
									text = display_name,
									radio = true,  -- mark as radio button
									checked_func = function()
										return book_settings.corner_font_face == path
									end,
									font_func = function(size)
										return Font:getFace(path, size)
									end,
									enabled_func = function()
										
										return book_settings.corner_font_face ~= path
									end,
									keep_menu_open = true,
									callback = function()
										
										book_settings.corner_font_face = path
										setBookSettings(book_id, book_settings)
										UIManager:setDirty("all", "ui")
									end,
								})
							end
						end

						return items
					end,
					hold_callback = function(touchmenu_instance)
					local current_font_path = book_settings.corner_font_face
					local current_font_name = _("not set")
					if current_font_path then
						for i, name in ipairs(cre.getFontFaces()) do
							if cre.getFontFaceFilenameAndFaceIndex(name) == current_font_path then
								current_font_name = name
								break
							end
						end
					end

					local default_font_path = headerDB:readSetting("default_corner_font_face")
					local default_font_name = _("not set")
					if default_font_path then
						for i, name in ipairs(cre.getFontFaces()) do
							if cre.getFontFaceFilenameAndFaceIndex(name) == default_font_path then
								default_font_name = name
								break
							end
						end
					end

					if current_font_path == default_font_path then
						UIManager:show(InfoMessage:new{
							text = T(_("Current corner font (%1) is already the default."), current_font_name),
							timeout = 2,
						})
						return
					end

					UIManager:show(ConfirmBox:new{
						text = T(_("Set current corner font (%1) as default?\n\nThe current default is %2."),
							current_font_name, default_font_name),
						ok_text = _("Yes"),
						cancel_text = _("Cancel"),
						ok_callback = function()
							if current_font_path then
								headerDB:saveSetting("default_corner_font_face", current_font_path)
								UIManager:show(InfoMessage:new{
									text = T(_("Default corner font set to: %1"), current_font_name),
									show_delay = 0.3,
									timeout = 2,
								})
								touchmenu_instance:updateItems()
								UIManager:setDirty("all", "ui")
							else
								UIManager:show(InfoMessage:new{
									text = _("No font selected to save as default."),
									timeout = 3,
								})
							end
						end,
					})
				end,
				-- separator = true,
				})
				-- Decorative corner glyphs
					table.insert(items, {
					text_func = function()
						
						local corner_topleft = book_settings.corner_tl or DEFAULT_CORNER_TL
						local corner_topright = book_settings.corner_tr or DEFAULT_CORNER_TR
						local corner_bottomleft = book_settings.corner_bl or DEFAULT_CORNER_BL
						local corner_bottomright = book_settings.corner_br or DEFAULT_CORNER_BR
						return T(_("Corner glyphs: %1 %2 %3 %4"), corner_topleft, corner_topright, corner_bottomleft, corner_bottomright)
					end,

					keep_menu_open = true,
					sub_item_table_func = function()
						
						local items = {}
						local path = book_settings.corner_font_face
						local font_key = path and filenameFromPath(path)

						local glyphs = CORNER_GLYPH_TABLE[font_key] or DEFAULT_GLYPHS
			-- Decorative corner margins
			table.insert(items, {
               text_func = function()
				
				local corner_margin_x = book_settings.corner_margin_x or DEFAULT_CORNER_MARGIN_X
				local corner_margin_y = book_settings.corner_margin_y or DEFAULT_CORNER_MARGIN_Y
				return T(_("Corner margins: %1 / %2"), corner_margin_x, corner_margin_y)
			end,
			keep_menu_open = true,
		--	help_text = _("test."),
			callback = function(touchmenu_instance)
				
				local current_corner_margin_x = book_settings.corner_margin_x or DEFAULT_CORNER_MARGIN_X
				local current_corner_margin_y = book_settings.corner_margin_y or DEFAULT_CORNER_MARGIN_Y
				local default_corner_margin_x = headerDB:readSetting("default_corner_margin_x") or DEFAULT_CORNER_MARGIN_X
				local default_corner_margin_y = headerDB:readSetting("default_corner_margin_y") or DEFAULT_CORNER_MARGIN_Y
                    local margin_widget 
					margin_widget = DoubleSpinWidget:new{
                        title_text = _("Margins"),
                        left_value = current_corner_margin_x,
						left_min = -500,
						left_max = 500,
						left_step = 1,
						left_hold_step = 5,
						left_text = _("Horizontal"),
						right_value = current_corner_margin_y,
						right_min = -500,
						right_max = 500,
						right_step = 1,
						right_hold_step = 5,
						right_text = _("Vertical"),
						left_default = default_corner_margin_x,
						right_default = default_corner_margin_y,
						default_text = T(_("Default values: %1 / %2"), default_corner_margin_x, default_corner_margin_y),
						width_factor = 0.6,
						--info_text = _([[Negative values reduce the gap.]]),
                        keep_shown_on_apply = true,
						
                        callback = function(left_corner_margin_x, right_corner_margin_y)
							book_settings.corner_margin_x = left_corner_margin_x
							book_settings.corner_margin_y = right_corner_margin_y
							setBookSettings(book_id, book_settings)
								UIManager:setDirty("all", "ui")
						end,
						extra_text = _("Set as default"),
						extra_callback = function(left_corner_margin_x, right_corner_margin_y)
							headerDB:saveSetting("default_corner_margin_x", left_corner_margin_x)
							headerDB:saveSetting("default_corner_margin_y", right_corner_margin_y)
							margin_widget.left_default  = left_corner_margin_x
							margin_widget.right_default = right_corner_margin_y
							margin_widget.default_text  = T(_("Default values: %1 / %2"), left_corner_margin_x, right_corner_margin_y)
							margin_widget:update()
							UIManager:setDirty("all", "ui")
						end,
					}
                    UIManager:show(margin_widget)
                end,
				})
				-- Decorative corner size
				table.insert(items, {
				text_func = function()
					
					local corner_size = book_settings.corner_size or DEFAULT_CORNER_SIZE
					return T(_("Corner size: %1"), corner_size)
				end,
				keep_menu_open = true,
                callback = function(touchmenu_instance)
                    
					local current_corner_size = book_settings.corner_size or DEFAULT_CORNER_SIZE
					local default_corner_size = headerDB:readSetting("default_corner_size") or DEFAULT_CORNER_SIZE
                    local spin_widget 
					spin_widget = SpinWidget:new{
                        title_text = _("Corner size"),
                        value = current_corner_size,
						default_value = default_corner_size,
                        value_min = 0,
                        value_max = 500,   
                        value_step = 1,
						value_hold_step = 5,
						--info_text = _([[Chicken legs.]]),
                        keep_shown_on_apply = true,
                        callback = function(cornersize)
                            if cornersize.value ~= nil then
                                book_settings.corner_size = cornersize.value
                                setBookSettings(book_id, book_settings)
								touchmenu_instance:updateItems()
								UIManager:setDirty("all", "ui")
                            end
                        end,
						extra_text = _("Set as default"),
						extra_callback = function(cornersize)
							headerDB:saveSetting("default_corner_size", cornersize.value)
							spin_widget.default_value  = cornersize.value
							spin_widget:update()
						end,
                    }
                    UIManager:show(spin_widget)
					end,
					--separator = true,
				})
				-- Decorative corner preview size
				table.insert(items, {
				text_func = function()
					
					local corner_preview_size = book_settings.corner_preview_size or DEFAULT_CORNER_PREVIEW_SIZE
					return T(_("Glyph preview size: %1"), corner_preview_size)
				end,
				keep_menu_open = true,
                callback = function(touchmenu_instance)
                    
					local current_corner_preview_size = book_settings.corner_preview_size or DEFAULT_CORNER_PREVIEW_SIZE
					local default_corner_preview_size = headerDB:readSetting("default_corner_preview_size") or DEFAULT_CORNER_PREVIEW_SIZE
                    local spin_widget 
					spin_widget = SpinWidget:new{
                        title_text = _("Corner preview size"),
                        value = current_corner_preview_size,
						default_value = default_corner_preview_size,
                        value_min = 0,
                        value_max = 500,   
                        value_step = 1,
						value_hold_step = 5,
						--info_text = _([[Trinkets and baubles for sale.]]),
                        keep_shown_on_apply = true,
                        callback = function(cornerpreviewsize)
                            if cornerpreviewsize.value ~= nil then
                                book_settings.corner_preview_size = cornerpreviewsize.value
                                setBookSettings(book_id, book_settings)
								touchmenu_instance:updateItems()
								UIManager:setDirty("all", "ui")
                            end
                        end,
						extra_text = _("Set as default"),
						extra_callback = function(cornerpreviewsize)
							headerDB:saveSetting("default_corner_preview_size", cornerpreviewsize.value)
							spin_widget.default_value  = cornerpreviewsize.value
							spin_widget:update()
						end,
                    }
                    UIManager:show(spin_widget)
					end,
					separator = true,
				})
					for _, glyph in ipairs(glyphs) do
					table.insert(items, {
						text_func = function()
								
								local tl = book_settings.corner_tl == glyph
								local tr = book_settings.corner_tr == glyph
								local bl = book_settings.corner_bl == glyph
								local br = book_settings.corner_br == glyph

								local suffix = ""
								if tl and tr and bl and br then
									suffix = " ⌜⌝⌞⌟"
								elseif tl and tr and bl then
									suffix = " ⌜⌝⌞"
								elseif tl and tr and br then
									suffix = " ⌜⌝⌟"
								elseif tl and bl and br then
									suffix = " ⌜⌞⌟"
								elseif tr and bl and br then
									suffix = " ⌝⌞⌟"
								elseif tl and tr then
									suffix = " ⌜⌝"
								elseif tl and bl then
									suffix = " ⌜⌞"
								elseif tl and br then
									suffix = " ⌜⌟"
								elseif tr and bl then
									suffix = " ⌝⌞"
								elseif tr and br then
									suffix = " ⌝⌟"
								elseif bl and br then
									suffix = " ⌞⌟"
								elseif tl then
									suffix = " ⌜"
								elseif tr then
									suffix = " ⌝"
								elseif bl then
									suffix = " ⌞"
								elseif br then
									suffix = " ⌟"
								end

								return glyph .. suffix
							end,
							radio = true,
							checked_func = function()
								return book_settings.corner_tl == glyph
									or book_settings.corner_tr == glyph
									or book_settings.corner_bl == glyph
									or book_settings.corner_br == glyph
							end,
						keep_menu_open = true,
						font_func = function(size)
							local current_size =
								book_settings.corner_preview_size or DEFAULT_CORNER_PREVIEW_SIZE
							return Font:getFace(path, current_size)
						end,
						
						callback = function(touchmenu_instance)
							UIManager:show(ConfirmBox:new{
								text = T(("Assign glyph '%1' to which corner?"), glyph),
								icon = "notice-question",
								no_ok_button = true, -- important
								other_buttons_first = true,
								other_buttons = {
									{
										{
											text = ("Top-left"),
											callback = function()
												book_settings.corner_tl = glyph
												setBookSettings(book_id, book_settings)
												touchmenu_instance:updateItems()
												UIManager:setDirty("all", "ui")
											end,
										},
										{
											text = ("Top-right"),
											callback = function()
												book_settings.corner_tr = glyph
												setBookSettings(book_id, book_settings)
												touchmenu_instance:updateItems()
												UIManager:setDirty("all", "ui")
											end,
										},
									},
									{
										{
											text = ("Bottom-left"),
											callback = function()
												book_settings.corner_bl = glyph
												setBookSettings(book_id, book_settings)
												touchmenu_instance:updateItems()
												UIManager:setDirty("all", "ui")
											end,
										},
										{
											text = ("Bottom-right"),
											callback = function()
												book_settings.corner_br = glyph
												setBookSettings(book_id, book_settings)
												touchmenu_instance:updateItems()
												UIManager:setDirty("all", "ui")
											end,
										},
									},
								},
							})
						end,
					})
				end
						return items
					end,
					hold_callback = function()

						local tl = book_settings.corner_tl or ""
						local tr = book_settings.corner_tr or ""
						local bl = book_settings.corner_bl or ""
						local br = book_settings.corner_br or ""

						local dtl = headerDB:readSetting("default_corner_tl") or ""
						local dtr = headerDB:readSetting("default_corner_tr") or ""
						local dbl = headerDB:readSetting("default_corner_bl") or ""
						local dbr = headerDB:readSetting("default_corner_br") or ""

						local function g(glyph)
							return glyph ~= "" and glyph or _("(None)")
						end

						local defaults_match =
							tl == dtl and tr == dtr and bl == dbl and br == dbr
						
						if defaults_match then
							UIManager:show(InfoMessage:new{
								text = T(_("Current corners: \n\nTop left: %1\nTop right: %2\nBottom left: %3\nBottom right: %4\n\nAre already the default."), g(tl), g(tr), g(bl), g(br)),
								timeout = 3,
							})
							return
						end
						
						UIManager:show(MultiConfirmBox:new{
							text = T(
								_("Set the current corners as defaults?\n\nTop left:   %1\nTop right: %2\nBottom left:  %3\nBottom right:  %4\n\nCurrent default (★):\nTop left:   %5\nTop right: %6\nBottom left:  %7\nBottom right:  %8"),
								g(tl), g(tr), g(bl), g(br),
								g(dtl), g(dtr), g(dbl), g(dbr)
							),

							choice1_text_func = function()
								return defaults_match
									and _("Set (★)")
									or  _("Set")
							end,
							choice1_callback = function()
								headerDB:saveSetting("default_corner_tl", tl)
								headerDB:saveSetting("default_corner_tr", tr)
								headerDB:saveSetting("default_corner_bl", bl)
								headerDB:saveSetting("default_corner_br", br)
							end,

							choice2_text_func = function()
								return defaults_match and _("Clear") or _("Clear")
							end,
							choice2_callback = function()
								headerDB:saveSetting("default_corner_tl", "")
								headerDB:saveSetting("default_corner_tr", "")
								headerDB:saveSetting("default_corner_bl", "")
								headerDB:saveSetting("default_corner_br", "")
							end,
						})
					end,
				separator = true,
				})
						return items
					end,
					separator = true,
				},
				
            -- Font size
            {
                text_func = function()
				local size = (book_settings.font_size and book_settings.font_size > 0) and book_settings.font_size or CRE_HEADER_DEFAULT_SIZE
				return T(_("Font size: %1"), size)
			end,
			callback = function(touchmenu_instance)
				
					local current_font_size = (book_settings.font_size and book_settings.font_size > 0 and book_settings.font_size)
                          or headerDB:readSetting("default_font_size")
                          or CRE_HEADER_DEFAULT_SIZE
					local default_size = headerDB:readSetting("default_font_size") or CRE_HEADER_DEFAULT_SIZE
                    local spin_widget 
					spin_widget = SpinWidget:new{
                        title_text = _("Font Size"),
                        value = current_font_size,
						default_value = default_size,
                        value_min = 1,
                        value_max = 96,
                        value_step = 1,
						--precision = "%.1f",
						--args = { -0.5, 0.5 },
						value_hold_step = 5,
						--unit = "pt",
                        keep_shown_on_apply = true,
                        callback = function(fontsize)
                            if fontsize.value then
                                book_settings.font_size = fontsize.value
                                setBookSettings(book_id, book_settings)
								touchmenu_instance:updateItems()
								UIManager:setDirty("all", "ui")
                            end
                        end,
						extra_text = _("Set as default"),
						extra_callback = function(fontsize)
							headerDB:saveSetting("default_font_size", fontsize.value)
							
                            touchmenu_instance:updateItems()
							spin_widget.default_value  = fontsize.value
							spin_widget:update()
						end,
                    }
                    UIManager:show(spin_widget)
                end,
            },
            -- Margin
            {
                text_func = function()
				
				local top_m = book_settings.top_header_margin or DEFAULT_TOP_HEADER_MARGIN
				local bottom_m = book_settings.bottom_header_margin or DEFAULT_BOTTOM_HEADER_MARGIN
				return T(_("Margins: %1 / %2"), top_m, bottom_m)
			end,
		--	help_text = _("test."),
			callback = function(touchmenu_instance)
				
				local current_top = book_settings.top_header_margin or DEFAULT_TOP_HEADER_MARGIN
				local current_bottom = book_settings.bottom_header_margin or DEFAULT_BOTTOM_HEADER_MARGIN
				local default_top = headerDB:readSetting("default_top_header_margin") or DEFAULT_TOP_HEADER_MARGIN
				local default_bottom = headerDB:readSetting("default_bottom_header_margin") or DEFAULT_BOTTOM_HEADER_MARGIN
                    local margin_widget 
					margin_widget = DoubleSpinWidget:new{
                        title_text = _("Top/Bottom Margin"),
                        left_value = current_top,
						left_min = -5000,
						left_max = 5000,
						left_step = 1,
						left_hold_step = 5,
						left_text = _("Top"),
						right_value = current_bottom,
						right_min = -5000,
						right_max = 5000,
						right_step = 1,
						right_hold_step = 5,
						right_text = _("Bottom"),
						left_default = default_top,
						right_default = default_bottom,
						default_text = T(_("Default values: %1 / %2"), default_top, default_bottom),
						width_factor = 0.6,
						--info_text = _([[Negative values reduce the gap.]]),
                        keep_shown_on_apply = true,
                        callback = function(top_val, bottom_val)
							book_settings.top_header_margin = top_val
							book_settings.bottom_header_margin = bottom_val
							setBookSettings(book_id, book_settings)
							touchmenu_instance:updateItems()
							UIManager:setDirty("all", "ui")
						end,
						extra_text = _("Set as default"),
						extra_callback = function(top_val, bottom_val)
							headerDB:saveSetting("default_top_header_margin", top_val)
							headerDB:saveSetting("default_bottom_header_margin", bottom_val)
							
                            touchmenu_instance:updateItems()
							margin_widget.left_default  = top_val
							margin_widget.right_default = bottom_val
							margin_widget.default_text  = T(_("Default values: %1 / %2"), top_val, bottom_val)
							margin_widget:update()
							UIManager:setDirty("all", "ui")
						end,
					}
                    UIManager:show(margin_widget)
                end,
            },
			-- Letter spacing for header title
            {
                text_func = function()
                    local spacing = book_settings.letter_spacing or DEFAULT_LETTER_SPACING
                    return T(_("Letter spacing: %1"), spacing)
                end,
                callback = function(touchmenu_instance)
                    
					local current_spacing = book_settings.letter_spacing or DEFAULT_LETTER_SPACING
					local default_spacing = headerDB:readSetting("default_letter_spacing") or DEFAULT_LETTER_SPACING
                    local spin_widget 
					spin_widget = SpinWidget:new{
                        title_text = _("Letter Spacing"),
                        value = current_spacing,
						default_value = default_spacing,
                        value_min = 0,
                        value_max = 100,   
                        value_step = 1,
						value_hold_step = 5,
                        keep_shown_on_apply = true,
                        callback = function(letterspacing)
                            if letterspacing.value ~= nil then
                                book_settings.letter_spacing = letterspacing.value
                                setBookSettings(book_id, book_settings)
								touchmenu_instance:updateItems()
								UIManager:setDirty("all", "ui")
                            end
                        end,
						extra_text = _("Set as default"),
						extra_callback = function(letterspacing)
							headerDB:saveSetting("default_letter_spacing", letterspacing.value)
                            touchmenu_instance:updateItems()
							spin_widget.default_value  = letterspacing.value
							spin_widget:update()
						end,
                    }
                    UIManager:show(spin_widget)
                end,
            },
			{

				text_func = function()
					local style = book_settings.header_style or 0
					local name = HEADER_STYLE_NAMES[style] or _("Unknown")
					return T(_("Font case: %1"), name)
				end,
				enabled_func = function()
                    return not (book_settings.two_column_mode or false)
                end,
				keep_menu_open = true,

				sub_item_table_func = function()
					
				local items = {}

				-- Original
				table.insert(items, {
                text = _("Original"),
				enabled_func = function()
                    return not (book_settings.two_column_mode or false)
                end,
                checked_func = function()
                    return book_settings.header_style == 0
                end,
				radio = true,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    book_settings.header_style = 0
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				})	
				-- Title case
				table.insert(items, {
                text = _("Title case"),
				enabled_func = function()
                    return not (book_settings.two_column_mode or false)
                end,
                checked_func = function()
                    --
                    return book_settings.header_style == 3
                end,
				radio = true,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    --
                    book_settings.header_style = 3
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				})	
				-- Uppercase
				table.insert(items, {
                text = _("Uppercase"),
				enabled_func = function()
                    return not (book_settings.two_column_mode or false)
                end,
                checked_func = function()
                    
                    return book_settings.header_style == 1
                end,
				radio = true,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    
                    book_settings.header_style = 1
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				})	
				-- Lowercase
				table.insert(items, {
                text = _("Lowercase"),
				enabled_func = function()
                    return not (book_settings.two_column_mode or false)
                end,
                checked_func = function()
                    
                    return book_settings.header_style == 2
                end,
				radio = true,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    
                    book_settings.header_style = 2
                    setBookSettings(book_id, book_settings)
                    touchmenu_instance:updateItems()
					UIManager:setDirty("all", "ui")
                end,
				})	
					return items
					end,
					--separator = true,
				},
            -- Font face
				{
				text_func = function()
					local path = book_settings.font_face
					local default_font_path = headerDB:readSetting("default_font_face")

					local function getFontName(file)
						local name_text, i = FontChooser.getFontNameText(file)
						if not name_text then
							name_text = _("Noto Serif")
						end
						return name_text
					end

					local display_name = getFontName(path)

					if default_font_path and path == default_font_path then
						display_name = T(_("Default (%1)"), display_name)
					end

					return T(_("Title font: %1"), display_name)
				end,

			callback = function(touchmenu_instance)
				local current_font = book_settings.font_face
				local default_font = headerDB:readSetting("default_font_face")

				local original_fontinfo = FontList.fontinfo
				local filtered_fontinfo = {}
				for file, info_table in pairs(original_fontinfo) do
					local copy_faces = {}
					for _, face_info in ipairs(info_table) do
						if not face_info.bold then
							copy_faces[#copy_faces+1] = face_info
						end
					end
					if #copy_faces > 0 then
						filtered_fontinfo[file] = copy_faces
					end
				end
				FontList.fontinfo = filtered_fontinfo

				local chooser = FontChooser:new{
					title = _("Select title font"),
					font_file = current_font,
					default_font_file = default_font,
					keep_shown_on_apply = true,
					callback = function(selected_font)
						
						book_settings.font_face = selected_font
						setBookSettings(book_id, book_settings)
						if touchmenu_instance then touchmenu_instance:updateItems() end
						UIManager:setDirty("all", "ui")
					end,
					close_callback = function()
						if touchmenu_instance then touchmenu_instance:updateItems() end
					end,
				}

				FontList.fontinfo = original_fontinfo
				UIManager:show(chooser)
			end,
			hold_callback = function(touchmenu_instance)
				
				local current_font = book_settings.font_face
				local default_font = headerDB:readSetting("default_font_face")

				local function getFontName(file)
					local name_text, i = FontChooser.getFontNameText(file)
					return name_text or _("Noto Serif")
				end

				if current_font == default_font then
					UIManager:show(InfoMessage:new{
						text = T(_("Current title font (%1) is already the default."), getFontName(current_font)),
						timeout = 2,
					})
					return
				end

				UIManager:show(ConfirmBox:new{
					text = T(_("Set current title font (%1) as default?\n\nThe current default is %2."),
						getFontName(current_font), getFontName(default_font)),
					ok_text = _("Yes"),
					cancel_text = _("Cancel"),
					ok_callback = function()
						if current_font then
							headerDB:saveSetting("default_font_face", current_font)
							UIManager:show(InfoMessage:new{
								text = T(_("Default title font set to: %1"), getFontName(current_font)),
								show_delay = 0.3,
								timeout = 2,
							})
							if touchmenu_instance then touchmenu_instance:updateItems() end
							UIManager:setDirty("all", "ui")
						end
					end,
				})
			end,
				--separator = true,
			},
			  -- Page number Font face
				{
				text_func = function()
					local path = book_settings.page_number_font_face
					local default_font_path = headerDB:readSetting("default_page_number_font_face")

					local function getFontName(file)
						local name_text, i = FontChooser.getFontNameText(file)
						if not name_text then
							name_text = _("Noto Serif")
						end
						return name_text
					end

					local display_name = getFontName(path)

					if default_font_path and path == default_font_path then
						display_name = T(_("Default (%1)"), display_name)
					end

					return T(_("Page font: %1"), display_name)
				end,
				
			callback = function(touchmenu_instance)
				local current_font = book_settings.page_number_font_face
				local default_font = headerDB:readSetting("default_page_number_font_face")

				local original_fontinfo = FontList.fontinfo
				local filtered_fontinfo = {}
				for file, info_table in pairs(original_fontinfo) do
					local copy_faces = {}
					for _, face_info in ipairs(info_table) do
						if not face_info.bold then
							copy_faces[#copy_faces+1] = face_info
						end
					end
					if #copy_faces > 0 then
						filtered_fontinfo[file] = copy_faces
					end
				end
				FontList.fontinfo = filtered_fontinfo

				local chooser = FontChooser:new{
					title = _("Select page number font"),
					font_file = current_font,
					default_font_file = default_font,
					keep_shown_on_apply = true,
					callback = function(selected_font)
						
						book_settings.page_number_font_face = selected_font
						setBookSettings(book_id, book_settings)
						if touchmenu_instance then touchmenu_instance:updateItems() end
						UIManager:setDirty("all", "ui")
					end,
					close_callback = function()
						if touchmenu_instance then touchmenu_instance:updateItems() end
					end,
				}
				FontList.fontinfo = original_fontinfo
				UIManager:show(chooser)
			end,
			hold_callback = function(touchmenu_instance)
				local current_font = book_settings.page_number_font_face
				local default_font = headerDB:readSetting("default_page_number_font_face")

				local function getFontName(file)
					local name_text, i = FontChooser.getFontNameText(file)
					return name_text or _("Noto Serif")
				end

				if current_font == default_font then
					UIManager:show(InfoMessage:new{
						text = T(_("Current page number font (%1) is already the default."), getFontName(current_font)),
						timeout = 2,
					})
					return
				end

				UIManager:show(ConfirmBox:new{
					text = T(_("Set current page number font (%1) as default?\n\nThe current default is %2."),
						getFontName(current_font), getFontName(default_font)),
					ok_text = _("Yes"),
					cancel_text = _("Cancel"),
					ok_callback = function()
						if current_font then
							headerDB:saveSetting("default_page_number_font_face", current_font)
							UIManager:show(InfoMessage:new{
								text = T(_("Default page number font set to: %1"), getFontName(current_font)),
								show_delay = 0.3,
								timeout = 2,
							})
							if touchmenu_instance then touchmenu_instance:updateItems() end
							UIManager:setDirty("all", "ui")
						end
					end,
				})
			end,
				separator = true,
			},
				-- About menu
				{
					text = _("About page header"),
					keep_menu_open = true,
					callback = function()
						local rotation = Screen:getRotationMode()
						local info_height
						local info_width
						if rotation == Screen.DEVICE_ROTATED_CLOCKWISE or rotation == Screen.DEVICE_ROTATED_COUNTERCLOCKWISE then
							info_height = Screen:scaleBySize(450)
							info_width = Screen:scaleBySize(500)
						else
							info_height = Screen:scaleBySize(650)
							info_width = Screen:scaleBySize(450)
						end
						UIManager:show(InfoMessage:new{
							height = info_height,
							width = info_width,
							face = Font:getFace("infont", 16),
							monospace_font = true,
							show_icon = false,
							text = about_text,
						})
					end,
				},
        },
    })
end

--------------------------------------------------------------------------
-- render header
--------------------------------------------------------------------------
local _ReaderView_paintTo_orig = ReaderView.paintTo
ReaderView.paintTo = function(self, bb, x, y)
    _ReaderView_paintTo_orig(self, bb, x, y)
    
    if self.render_mode ~= nil then
        --logger.err("paintTo: early return (render_mode set)")
        return
    end
		--logger.warn("paintTo called", "self:", tostring(self), "ui:", tostring(self.ui))
	
	local reader_for_id = (self.ui and self.ui.reader) or self
	if not reader_for_id then
		--logger.err("paintTo: no reader available for this view")
		return
	end

	local book_settings, book_id = ensureBookSettings(reader_for_id)
	if not book_settings or not book_id then
		--logger.err("paintTo: failed to get book settings or book ID")
		return
	end

	--logger.warn("paintTo: book_id:", tostring(book_id))
	--logger.warn("paintTo: book_settings keys:", next(book_settings) ~= nil)
	
    local pageno = self.state.page or 1
    local pages  = self.ui.doc_settings.data.doc_pages or 1
	local book_pageturn = pageno
	
	-- book title
	local book_title = ""
    local book_author = ""
	local book_language = ""
    if self.ui.doc_props then
        book_title = self.ui.doc_props.display_title or ""
        book_author = self.ui.doc_props.authors or ""
		book_language = self.ui.doc_props.language or ""
        if book_author:find("\n") then -- Show first author if multiple authors
            book_author =  T(_("%1"), util.splitToArray(book_author, "\n")[1])
        end
    end
    -- book chapter
    local book_chapter = ""
    local pages_chapter = 0
    local pages_left = 0
    local pages_done = 0
	max_toc_depth = self.ui.toc:getMaxDepth() or 1
	local selected_toc_level = book_settings.chapter_toc_depth or max_toc_depth or 0
    if self.ui.toc then
        pages_chapter = self.ui.toc:getChapterPageCount(pageno) or pages
        pages_left = self.ui.toc:getChapterPagesLeft(pageno) or self.ui.document:getTotalPagesLeft(pageno)
        pages_done = self.ui.toc:getChapterPagesDone(pageno) or 0
		if max_toc_depth == 1 or selected_toc_level == 0  then 
			book_chapter = self.ui.toc:getTocTitleByPage(pageno) or ""
		else
			local ch
			local ch_list = self.ui.toc:getFullTocTitleByPage(pageno) 	--table with ch titles from all toc 
																		--levels for curr. pageno
			for i = selected_toc_level, 1, -1 do
				if ch_list[i] and ch_list [i] ~= "" then 
					ch = ch_list[i]
					break
				end
			end
			book_chapter = ch or self.ui.toc:getTocTitleByPage(pageno) or ""
		end
    end
	
    local header_font_face = book_settings.font_face or DEFAULT_HEADER_FACE
	local page_font_face = book_settings.page_number_font_face or DEFAULT_PAGE_NUMBER_FONT_FACE

    local header_font_size = book_settings.font_size or CRE_HEADER_DEFAULT_SIZE
    local top_header_margin = book_settings.top_header_margin or DEFAULT_TOP_HEADER_MARGIN
	local bottom_header_margin = book_settings.bottom_header_margin or DEFAULT_BOTTOM_HEADER_MARGIN
	
	local header_font_color  = Blitbuffer.COLOR_BLACK
	local key = book_settings.fleuron_color or DEFAULT_FLEURON_COLOR_KEY
	local fleuron_font_color  = COLOR_KEY_TO_VALUE[key] or Blitbuffer.COLOR_BLACK
	
    local screen_width = Screen:getWidth()
	local screen_height = Screen:getHeight()
	
	-- Divider
	local divider_glyph = book_settings.divider_glyph or headerDB:readSetting("default_divider_glyph") or DEFAULT_DIVIDER_GLYPH
	local divider_font_face = book_settings.divider_font_face or headerDB:readSetting("default_divider_font_face") or DEFAULT_DIVIDER_FONT_FACE
	local divider_size = book_settings.divider_size or headerDB:readSetting("default_divider_size") or DEFAULT_DIVIDER_SIZE
	local divider_margin = book_settings.divider_margin or headerDB:readSetting("default_divider_margin")or DEFAULT_DIVIDER_MARGIN
	local divider_gap = book_settings.divider_padding or headerDB:readSetting("default_divider_padding")or DEFAULT_DIVIDER_PADDING

	--flourish
	local lflo = book_settings.fleuron_left or headerDB:readSetting("default_fleuron_left") or DEFAULT_FLEURON_LEFT
	local rflo = book_settings.fleuron_right or headerDB:readSetting("default_fleuron_right") or DEFAULT_FLEURON_RIGHT
	local mflo = book_settings.fleuron_middle or headerDB:readSetting("default_fleuron_middle") or DEFAULT_FLEURON_MIDDLE
	local flo_gap = book_settings.fleuron_margin or headerDB:readSetting("default_fleuron_margin") or DEFAULT_FLEURON_MARGIN
	local flo_size = book_settings.fleuron_size or headerDB:readSetting("default_fleuron_size") or DEFAULT_FLEURON_SIZE
	local flo_height = book_settings.fleuron_height or headerDB:readSetting("default_fleuron_height") or DEFAULT_FLEURON_HEIGHT
	local flo_face_name = book_settings.fleuron_font_face or headerDB:readSetting("default_fleuron_font_face") or DEFAULT_FLEURON_FONT_FACE
	
	--corner
	local corner_font_face = book_settings.corner_font_face or headerDB:readSetting("default_corner_font_face") or DEFAULT_CORNER_FONT_FACE
	local corner_font_size = book_settings.corner_size or headerDB:readSetting("default_corner_size") or DEFAULT_CORNER_SIZE
	local corner_margin_x = book_settings.corner_margin_x or headerDB:readSetting("default_corner_margin_x") or DEFAULT_CORNER_MARGIN_X
	local corner_margin_y = book_settings.corner_margin_y or headerDB:readSetting("default_corner_margin_y") or DEFAULT_CORNER_MARGIN_Y
				
	local CORNER_TL = book_settings.corner_tl or headerDB:readSetting("default_corner_tl") or DEFAULT_CORNER_TL
	local CORNER_TR = book_settings.corner_tr or headerDB:readSetting("default_corner_tr") or DEFAULT_CORNER_TR
	local CORNER_BL = book_settings.corner_bl or headerDB:readSetting("default_corner_bl") or DEFAULT_CORNER_BL
	local CORNER_BR = book_settings.corner_br or headerDB:readSetting("default_corner_br") or DEFAULT_CORNER_BR
	
    -- Per-book show/hide flags
    local hide_title = book_settings.hide_title
    local hide_page  = book_settings.hide_page_number
    local page_bottom = book_settings.page_bottom_center
    local alternate_page_align = book_settings.alternate_page_align
	local two_column_mode = book_settings.two_column_mode

    -- Determine if first page of chapter
    local first_page_of_chapter = false
   	if self.ui.toc then 
        first_page_of_chapter = (self.ui.toc:isChapterStart(book_pageturn))
    end
	
	local cover_page = false
	if book_settings.childchapter_page then
		if self.ui and self.ui.toc then
			local toc = self.ui.toc
			local index = toc:getTocIndexByPage(pageno)

			if index and toc.toc and toc.toc[index] then
				local item = toc.toc[index]

				if item.page == pageno then
					local depth = item.depth

					-- Look ahead to see if this node has children
					local next_item = toc.toc[index + 1]
					local has_children = next_item and next_item.depth > depth

					if depth == 1 then
						if has_children then
							-- Top structural node with children → cover page
							cover_page = true
							first_page_of_chapter = false
						else
							-- Top structural node without children → treat as first page of chapter
							--cover_page = false
							first_page_of_chapter = true
						end
					else
						-- Any child node → not a first page of chapter
						cover_page = false
						first_page_of_chapter = false
					end
				end
			end
		end
	end
	
	local header_choice = book_settings.book_header_source or "title"
	local resolved_book_title = book_title

	if header_choice == "author" then
		resolved_book_title = book_author or ""

	elseif header_choice:match("^toc:") then
		local depth = tonumber(header_choice:match(":(%d+)")) or 1
		if self.ui.toc then
			local ch_list = self.ui.toc:getFullTocTitleByPage(pageno) or {}
			resolved_book_title = ch_list[depth] or ""
		end
	end

	-- Decide what to show for the header text
	local centered_header = ""

	if not hide_title and not first_page_of_chapter then

		if always_chapter then
			centered_header = book_chapter
		else
			if pageno % 2 == 1 then
				centered_header = (resolved_book_title ~= "" and resolved_book_title) or book_chapter
			else
				centered_header = (book_chapter ~= "" and book_chapter) or resolved_book_title
			end
		end
	end
	
	if book_settings.hide_chapter_word == true then
		local rest = centered_header:match(
			"^[Cc][Hh][Aa][Pp][Tt][Ee][Rr]%s+[%dIVXLCDMivxlcdm]+[%s%p]+(.+)"
		)
		if rest then centered_header = rest
		else
			local rest2 = centered_header:match(
				"^[%dIVXLCDMivxlcdm]+[%s%p]+(.+)"
			)
			if rest2 then centered_header = rest2
			end
		end
	end
	local book_title      = book_title
	local book_chapter    = book_chapter

	-- apply case transforms HERE
	local header_style = book_settings.header_style
	if header_style == 1 then
		centered_header = string.upper(centered_header)
	elseif header_style == 2 then
		centered_header = string.lower(centered_header)
	elseif header_style == 3 then
		centered_header = titlecase(centered_header)
	end
	
	local letter_spacing = tonumber(book_settings.letter_spacing) or DEFAULT_LETTER_SPACING

	local header_for_fitting = centered_header
	local spaced_book_title = book_title
	local spaced_book_chapter = book_chapter

	if letter_spacing > 0 then
		if header_for_fitting ~= "" then
			header_for_fitting = utf8_spaced(header_for_fitting, letter_spacing)
		end

		if spaced_book_title ~= "" then
			spaced_book_title = utf8_spaced(spaced_book_title, letter_spacing)
		end

		if spaced_book_chapter ~= "" then
			spaced_book_chapter = utf8_spaced(spaced_book_chapter, letter_spacing)
		end
	end
    -- Fit text (respect page margins)
    local page_margins = (self.document and self.document.getPageMargins) and self.document:getPageMargins() or {}
    local left_margin  = page_margins.left or top_header_margin
    local right_margin = page_margins.right or top_header_margin
	local top_margin    = page_margins.top or top_header_margin
	local bottom_margin = page_margins.bottom or bottom_header_margin

    local avail_width  = screen_width - (left_margin + right_margin)

	local function getFittedText(text, max_width_px)
    if not text or text == "" then
        return ""
    end

    local clean_text = text:gsub(" ", "\u{00A0}")
    local text_widget = TextWidget:new{
        text      = clean_text,
        max_width = max_width_px,
        face      = Font:getFace(header_font_face, header_font_size),
        padding   = 0,
    }

    local fitted_text, add_ellipsis = text_widget:getFittedText()
    text_widget:free()
    if add_ellipsis then
        fitted_text = fitted_text .. "…"
    end
	return BD.auto(fitted_text)
end

    local col_width = math.floor(avail_width / 2)
    local left_start  = left_margin
    local right_start = left_margin + col_width
	
	local fitted_centered = getFittedText(header_for_fitting, avail_width)
	local left_fitted  = getFittedText(book_title, col_width)
	local right_fitted = getFittedText(book_chapter, col_width)

    -- Decide what to show for the page indicator (string). Prefer reference labels when enabled.
    local display_page_text = nil

    -- Check per-document setting first
    local use_ref = nil
    if self.ui and self.ui.doc_settings and self.ui.doc_settings.readSetting then
        use_ref = self.ui.doc_settings:readSetting("pagemap_use_page_labels")
    end
    if use_ref == nil then
        use_ref = headerDB:isTrue("pagemap_use_page_labels")
    end

    if use_ref and self.ui and self.ui.document and self.ui.document.getPageMapCurrentPageLabel then
        local label = self.ui.document:getPageMapCurrentPageLabel()
        if type(label) == "string" and label ~= "" then
            display_page_text = label
        elseif type(label) == "table" and label[1] and label[1] ~= "" then
            display_page_text = label[1]
        end
    end

    if not display_page_text then
        display_page_text = tostring(pageno)
    end
	
	-- Absolute first pages (numeric) or reference page "i", "ii", etc.
	
	if pageno == 1 or pageno == 2 then
		cover_page = true
	end
	
	-- Also check reference labels
	if display_page_text then
		-- normalize to lowercase string
		local ref = tostring(display_page_text):lower()
		if ref == "1" or ref == "2" or ref == "i" or ref == "ii" then
			cover_page = true
		end
	end
	
	if book_settings.titlepage_to_cover then
		if self.ui and self.ui.toc then
			local toc = self.ui.toc
			local index = toc:getTocIndexByPage(pageno)

			if index and toc.toc and toc.toc[index] then
				local item = toc.toc[index]

				-- ensure this page is EXACT start of that toc entry
				if item.page == pageno then

					local current_depth = item.depth
					local has_children = false

					-- look ahead to see if next entry is deeper
					local next_item = toc.toc[index + 1]
					if next_item and next_item.depth > current_depth then
						has_children = true
					end

					if has_children then
						-- Structural node (Part / Book)
						cover_page = true
					else
						-- Leaf node (real chapter, even if level 1)
						first_page_of_chapter = true
					end
				end
			end
		end
	end

		local page_text = TextWidget:new{
				text    = display_page_text,
				face    = Font:getFace(page_font_face, header_font_size),
				fgcolor = header_font_color,
				padding = 0,
        }
		
		local function centerRow(total_w, screen_w)
			return (screen_w - total_w) / 2
		end

		local function centerOn(anchor_x, anchor_w, widget_w)
			return anchor_x + anchor_w / 2 - widget_w / 2
		end

		local function vAlign(anchor_h, widget_h, raise)
			return math.floor((anchor_h - widget_h) / 2) - (raise or 0)
		end
		
			local fleuron_face = Font:getFace(flo_face_name, flo_size)
			local left_fl = TextWidget:new{
				text = lflo,
				face = fleuron_face,
				fgcolor = fleuron_font_color,
				padding = 0,
			}
			local pg = TextWidget:new{
				text = tostring(display_page_text),
				face = Font:getFace(page_font_face, header_font_size),
				fgcolor = header_font_color,
				padding = 0,
			}
			local right_fl = TextWidget:new{
				text = rflo,
				face = fleuron_face,
				fgcolor = fleuron_font_color,
				padding = 0,
			}
			local middle_fl = TextWidget:new{
				text = mflo,
				face = fleuron_face,
				fgcolor = fleuron_font_color,
				padding = 0,
			}
			-- sizes
			local lw = left_fl:getSize().w
			local pw = pg:getSize().w
			local rw = right_fl:getSize().w
			local pg_h = pg:getSize().h
			local fl_h = left_fl:getSize().h
			local mf_h = middle_fl:getSize().h
			-- total width
			local total_w = lw + flo_gap + pw + flo_gap + rw
			-- base position
			local x = centerRow(total_w, screen_width)
			local y = screen_height - bottom_margin + bottom_header_margin
			-- alignment
			local raise = flo_height
			local v_offset = vAlign(pg_h, fl_h, raise)
			-- page number anchor
			local pg_x = x + lw + flo_gap
			-- middle flourish anchored to page number
			local mf_x = centerOn(pg_x, pw, middle_fl:getSize().w)
			local mf_y = y + vAlign(pg_h, mf_h, raise) - mf_h
    
	-- Page text widget
		if not hide_page and not two_column_mode and not cover_page then
		
		if not first_page_of_chapter then
			middle_fl:paintTo(bb, mf_x, y + v_offset)
		end	
		-- bottom centered
		if page_bottom or first_page_of_chapter then

			-- draw
			left_fl:paintTo(bb, x, y + v_offset)
			pg:paintTo(bb, pg_x, y)
			right_fl:paintTo(bb, pg_x + pw + flo_gap, y + v_offset)
			--middle_fl:paintTo(bb, mf_x, y + v_offset)
			-- cleanup
			left_fl:free()
			pg:free()
			right_fl:free()
			middle_fl:free()
		else
			-- always top right
			if not alternate_page_align then
				local page_x = screen_width - right_margin - page_text:getSize().w
				local page_y = top_margin - page_text:getSize().h - top_header_margin
				page_text:paintTo(bb, page_x, page_y)
			else
				-- alternate align
				local show_book = (pageno % 2 == 1 and book_title ~= "") or (pageno % 2 == 0 and book_chapter == "")
				-- top alternate align
				local page_w = page_text:getSize().w
				local page_h = page_text:getSize().h
				local fl_w = left_fl:getSize().w
				local fl_h = left_fl:getSize().h

				local page_x = show_book
					and left_margin
					or (screen_width - right_margin - page_w)

				local page_y = top_margin - page_h - top_header_margin
				local raise = flo_height or 0
				local lf_h = left_fl and left_fl:getSize().h or 0
				local rf_h = right_fl and right_fl:getSize().h or 0
				local v_offset_top = math.floor((page_h - math.max(lf_h, rf_h)) / 2) - raise

				-- draw page number
				page_text:paintTo(bb, page_x, page_y)


				-- draw only the appropriate fleuron
				if show_book then
					-- left page: page number on left, draw RIGHT fleuron
					if rflo ~= "" then
						local fl_x = page_x + page_w + flo_gap
						right_fl:paintTo(bb, fl_x, page_y + v_offset_top)
					end
				else
					-- right page: page number on right, draw LEFT fleuron
					if lflo ~= "" then
						local fl_x = page_x - flo_gap - fl_w
						left_fl:paintTo(bb, fl_x, page_y + v_offset_top)
					end
				end
							--middle_fl:paintTo(bb, mf_x, y + v_offset)
						
						end
					end

					page_text:free()
				end
	
	if two_column_mode then
		local avg_margin = (left_margin + right_margin) / 2
		local column_gap = math.max(Screen:scaleBySize(2), avg_margin * 0.5)
		local col_width = math.floor((avail_width - column_gap) / 2)
		local left_start  = left_margin
		local right_start = left_start + col_width + column_gap
		local balance_factor = 0.35
		local visual_center_offset = 0
		-- Left column
		if not first_page_of_chapter then
			if not hide_page then
				local left_page = TextWidget:new{
					text = display_page_text,
					face = Font:getFace(page_font_face, header_font_size),
					fgcolor = header_font_color,
				}
				local pageleft_y = top_margin - left_page:getSize().h - top_header_margin
				left_page:paintTo(bb, left_start, pageleft_y)
				left_page:free()
			end
			if not hide_title and book_title ~= "" then

				local left_safe_left = left_start
				local left_safe_right = left_start + col_width - (column_gap / 2)
				if not hide_page then
					local tmp_page = TextWidget:new{
						text = tostring(display_page_text),
						face = Font:getFace(page_font_face, header_font_size),
					}
					local left_page_w = tmp_page:getSize().w
					visual_center_offset = -left_page_w * balance_factor
					tmp_page:free()
					
					local gap = math.max(Screen:scaleBySize(16), header_font_size * 0.3)
					left_safe_left = left_safe_left + left_page_w + gap
				end
				local safe_width = math.max(left_safe_right - left_safe_left, 0)

				local left_fitted = getFittedText(spaced_book_title, safe_width)
				local left_text = TextWidget:new{
					text = left_fitted,
					face = Font:getFace(header_font_face, header_font_size),
					fgcolor = header_font_color,
					max_width = safe_width,
					truncate_with_ellipsis = true,
				}
				local text_w = left_text:getSize().w
				local text_x = left_safe_left + math.max((safe_width - text_w) / 2, 0) + visual_center_offset
				local textleft_y = top_margin - left_text:getSize().h - top_header_margin
				left_text:paintTo(bb, text_x, textleft_y)
				left_text:free()

			end
		end
		-- Right column
		if not first_page_of_chapter then
			local next_page_label
			local current_page_num = tonumber(display_page_text)

			if current_page_num then
				next_page_label = tostring(current_page_num + 1)
			else
				next_page_label = tostring(display_page_text)
			end

			if not hide_page then
				local right_page = TextWidget:new{
					text = next_page_label,
					face = Font:getFace(page_font_face, header_font_size),
					fgcolor = header_font_color,
				}
				local page_w = right_page:getSize().w
				local page_x = right_start + col_width - page_w
				local pageright_y = top_margin - right_page:getSize().h - top_header_margin
				right_page:paintTo(bb, page_x, pageright_y)
				right_page:free()
			end
			if not hide_title and book_chapter ~= "" then
				local right_safe_left = right_start + (column_gap / 2)
				local right_safe_right = right_start + col_width
				if not hide_page then
					local tmp_page = TextWidget:new{
					text = next_page_label,
					face = Font:getFace(page_font_face, header_font_size),
				}
				local right_page_w = tmp_page:getSize().w
				visual_center_offset = right_page_w * balance_factor
				tmp_page:free()
				
				local gap = math.max(Screen:scaleBySize(16), header_font_size * 0.3)
				right_safe_right = right_safe_right - right_page_w - gap
				end
				local safe_width = math.max(right_safe_right - right_safe_left, 0)

				local right_fitted = getFittedText(spaced_book_chapter, safe_width)
				local right_text = TextWidget:new{
					text = right_fitted,
					face = Font:getFace(header_font_face, header_font_size),
					fgcolor = header_font_color,
					max_width = safe_width,
					truncate_with_ellipsis = true,
				}
				local text_w = right_text:getSize().w
				local text_x = right_safe_left + math.max((safe_width - text_w) / 2, 0) + visual_center_offset
				local textright_y = top_margin - right_text:getSize().h - top_header_margin
				right_text:paintTo(bb, text_x, textright_y)
				right_text:free()

			end
		end
	elseif not cover_page then
				local page_text = TextWidget:new{
					text    = display_page_text,
					face    = Font:getFace(page_font_face, header_font_size),
					fgcolor = header_font_color,
				}
				local page_w = page_text:getSize().w
				page_text:free()
				
				local fleuron_gap = flo_gap or 0
				local left_fl_w = left_fl:getSize().w
				local right_fl_w = right_fl:getSize().w
				local left_fl_offs = (left_fl_w > 0 and left_fl_w + fleuron_gap or 0)
				local right_fl_offs = (right_fl_w > 0 and right_fl_w + fleuron_gap or 0)

				local gap = math.max(Screen:scaleBySize(16), header_font_size * 0.3)
				
				local safe_left  = left_margin
				local safe_right = screen_width - right_margin
				
					local divider = TextWidget:new{
						text    = divider_glyph,
						face    = Font:getFace(divider_font_face, divider_size),
						fgcolor = header_font_color,
						padding = 0,
					}

					local div_w = divider:getSize().w
					local div_h = divider:getSize().h
				
				local div_gap = divider_gap or 0
				local div_fl_gap = (div_w > 0 and div_w + div_gap or 0)

				local show_book = (pageno % 2 == 1 and book_title ~= "") 
							   or (pageno % 2 == 0 and book_chapter == "")
				
				local flipper = book_settings.divider_flip
				-- Adjust safe bounds for page number + optional fleuron if page is visible
				if not hide_page and (not page_bottom or book_settings.align_title_page) then
					if show_book then
						-- left-side page/book: adjust safe_left
						safe_left = safe_left + page_w + right_fl_offs + fleuron_gap + gap 
						if not page_bottom and not book_settings.align_title_page and flipper then
							safe_left = safe_left
						elseif page_bottom and book_settings.align_title_page and not flipper then
							safe_left = left_margin + div_fl_gap
						elseif page_bottom and book_settings.align_title_page and flipper then
							safe_left = left_margin
						end
					else
						-- right-side page: adjust safe_right
						safe_right = safe_right - page_w - left_fl_offs - fleuron_gap - gap
						if not page_bottom and not book_settings.align_title_page and flipper then
							safe_right = safe_right - gap
						elseif page_bottom and book_settings.align_title_page and not flipper then
							safe_right = (screen_width - right_margin) - div_fl_gap
						elseif page_bottom and book_settings.align_title_page and flipper then
							safe_right = screen_width - right_margin
						end
					end
				end
				local safe_width
				
				if page_bottom and book_settings.align_title_page and flipper then
					safe_width = math.max(safe_right - div_fl_gap - safe_left, 0)
				elseif not page_bottom and book_settings.align_title_page then
					safe_width = math.max(safe_right - div_fl_gap - gap - safe_left, 0)
				elseif not page_bottom and not book_settings.align_title_page and flipper then
					safe_width = math.max(safe_right - div_fl_gap - gap - safe_left, 0)
				else
					safe_width = math.max(safe_right - safe_left, 0)
				end
				
				-- header widget
				local header_text = TextWidget:new{
					text      = fitted_centered,
					face      = Font:getFace(header_font_face, header_font_size),
					fgcolor   = header_font_color,
					max_width = safe_width,
					truncate_with_ellipsis = true,
					padding   = 0,
				}

				local header_w = header_text:getSize().w
				local header_h = header_text:getSize().h

				local header_y = top_margin - header_h - top_header_margin

				-- compute alignment
				local header_x

				if book_settings.align_title_side and not page_bottom then
					header_x = show_book and (screen_width - right_margin - header_w) or safe_left
				elseif book_settings.align_title_page and page_bottom then
					header_x = show_book and safe_left or (safe_right - header_w)
				elseif book_settings.align_title_page then
					header_x = show_book and safe_left or (safe_right - header_w )
				else
					header_x = (screen_width - header_w) / 2
				end

				-- clamp inside bounds
				header_x = math.max(safe_left, math.min(header_x, safe_right - header_w))

				-- paint header
				header_text:paintTo(bb, header_x, header_y)

				-- divider
				if fitted_centered ~= "" then

					local div_y = header_y + (header_h - div_h) / 2 + divider_margin

					local div_x
					
					-- aligns at title start div_x = show_book and safe_left or (safe_right - div_w)
					local div_x = (screen_width - div_w) / 2

					if book_settings.align_title_page and not page_bottom then
						div_y = header_y + header_h - div_h + divider_margin
						-- lines up under the header div_y = header_y + (header_h - div_h) / 2 + divider_margin
						div_x = show_book and (screen_width - right_margin - div_w) or safe_left
					elseif book_settings.align_title_side then
						local div_y = header_y + (header_h - div_h) / 2 + divider_margin
						local div_x = (screen_width - div_w) / 2
					elseif not page_bottom and not book_settings.align_title_page and flipper then
						div_y = header_y + header_h - div_h + divider_margin
						div_x = show_book and (screen_width - right_margin - div_w) or left_margin
					elseif book_settings.align_title_page and page_bottom and not flipper then
						div_y = header_y + header_h - div_h + divider_margin
						div_x = show_book and left_margin or (screen_width - right_margin - div_w)
					elseif book_settings.align_title_page and page_bottom and flipper then
						div_y = header_y + header_h - div_h + divider_margin
						div_x = show_book and (left_margin + header_w + div_gap) or (screen_width - right_margin - header_w - div_fl_gap)
					end
						divider:paintTo(bb, div_x, div_y)
						divider:free()
					end

				header_text:free()
				
				local corner_face = Font:getFace(corner_font_face, corner_font_size)
				
				local function drawCornerGlyph(bb, glyph, face, x, y, color)
					local w = TextWidget:new{
						text = glyph,
						face = face,
						fgcolor = color,
						padding = 0,
					}
					w:paintTo(bb, x, y)
					w:free()
				end
		
				local function measureGlyph(glyph, face)
					if not glyph or glyph == "" then
						return 0, 0
					end

					local probe = TextWidget:new{
						text = glyph,
						face = face,
						padding = 0,
					}
					local size = probe:getSize()
					probe:free()

					return size.w or 0, size.h or 0
				end

				local tl_w, tl_h = measureGlyph(CORNER_TL, corner_face)
				local tr_w, tr_h = measureGlyph(CORNER_TR, corner_face)
				local bl_w, bl_h = measureGlyph(CORNER_BL, corner_face)
				local br_w, br_h = measureGlyph(CORNER_BR, corner_face)

				local top_y    = corner_margin_y
				local bottom_y = screen_height - corner_margin_y

				local left_x  = corner_margin_x
				local right_x = screen_width - corner_margin_x

					if CORNER_TL ~= "" then
						drawCornerGlyph( bb, CORNER_TL, corner_face,	left_x, top_y, header_font_color )
					end
					if CORNER_TR ~= "" then
						drawCornerGlyph( bb, CORNER_TR, corner_face, right_x - tr_w, top_y, header_font_color )
					end
					if CORNER_BL ~= "" then
						drawCornerGlyph( bb, CORNER_BL, corner_face, left_x, bottom_y - bl_h, header_font_color )
					end
					if CORNER_BR ~= "" then
						drawCornerGlyph( bb, CORNER_BR, corner_face, right_x - br_w, bottom_y - br_h, header_font_color )
					end

	end
end

function ReaderFooter:onFlushSettings()
    headerDB:flush()
end

-- How long will tomorrow last?
-- Eternity and a day.
