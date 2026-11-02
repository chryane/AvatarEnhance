--[[ Options.lua - 选项面板 (Settings API, 选项-插件分类)
	 面板铺满设置画布, 内容宽度跟随滚动区, 宽度变化即整份重排;
	 五个区域各一个带亮边的盒子, 总开关未启用时子项置灰。
]]

local ADDON_NAME, ns = ...
local config = ns.config

local options = {}
ns.options = options

local REGIONS = {
	{ key = "player", title = "玩家", subs = { "class", "role" } },
	{ key = "target", title = "目标", subs = { "class", "role" } },
	{ key = "focus",  title = "焦点", subs = { "class" } },
	{ key = "party",  title = "队伍", subs = { "class", "role", "level" } },
	{ key = "raid",   title = "团队", subs = { "role" } },
}

-- 子项: 显示名 / 配置键后缀
local SUBS = {
	class = { "职业", "Class" },
	role  = { "职责", "Role" },
	level = { "等级", "Level" },
}

local PANEL_W, PANEL_H = 640, 560

local LABEL_X       = 4
local TITLE_Y       = -8
local TITLE_LINE_DY = 38
local TITLE_GAP     = 14
local TITLE_LINE_Y  = TITLE_Y - TITLE_LINE_DY
local SCROLL_TOP    = TITLE_LINE_Y - TITLE_GAP
local SCROLL_RIGHT  = 14 -- 右缘: 让出滚动条本体
local CONTENT_W     = PANEL_W - LABEL_X - SCROLL_RIGHT

local BOX_INSET  = 8  -- 盒子右缘比内容窄 8: 躲开滚动条箭头
local BOX_PAD    = 10 -- 子项到盒子左/上边距
local ROW_H      = 26 -- 勾选行距
local CB_H       = 32 -- UICheckButtonTemplate 原生高度, 盒子要按它算高
local HEADER_H   = 20 -- 区域标题行占位(仅用于内容总高估算)
local HEADER_GAP = 2  -- 区域标题到盒子上边
local REGION_GAP = 14 -- 区域间距

-- 滚动条几何照抄系统设置面板(MinimalScrollBar 8px 宽, 箭头左右各溢约 4.5px)
local BAR_DY_TOP, BAR_DY_BOTTOM = -4, 7
local BAR_X_TOP, BAR_X_BOTTOM = 0, -1

local FONT_STEP = 2 -- 模板字号各客户端不一致, 统一按当前字号偏移

local regions = {} -- 每区 { box, cbs = { { cb, col, row } }, master, masterKey, subs }

local function GrowFont(fs)
	local path, size, flags = fs:GetFont()
	if path and size then fs:SetFont(path, size + FONT_STEP, flags) end
end

-- 细亮边盒子(照系统设置面板): 底色 alpha=0 只要那一圈
local function CreateBox(parent)
	local box = CreateFrame("Frame", nil, parent, "TooltipBackdropTemplate")
	box:SetBackdropColor(0, 0, 0, 0)
	box:SetBackdropBorderColor(0.62, 0.62, 0.62, 1)
	box.NineSlice:SetFrameLevel(box:GetFrameLevel()) -- NineSlice 默认层级很高, 会盖住勾选框
	return box
end

function options:Init()
	local panel = CreateFrame("Frame")
	panel.name = ADDON_NAME
	panel:SetSize(PANEL_W, PANEL_H)
	-- CreateFrame 默认可见, 不先藏起来则设置界面挂载本面板时不会触发 OnShow
	panel:Hide()
	self.panel = panel

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
	title:SetJustifyH("LEFT")
	title:SetText("AvatarEnhance - 头像增强")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", LABEL_X, TITLE_Y)

	-- useAtlasSize: 高度交给 atlas 原生粗细, 宽度靠左右两锚点撑开
	local line = panel:CreateTexture(nil, "ARTWORK")
	line:SetAtlas("Options_HorizontalDivider", true)
	line:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, TITLE_LINE_Y)
	line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, TITLE_LINE_Y)

	local scroll = CreateFrame("ScrollFrame", nil, panel)
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", LABEL_X, SCROLL_TOP)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SCROLL_RIGHT, 4)
	self.scroll = scroll

	-- 本客户端的 SCROLL_FRAME_SCROLL_BAR_TEMPLATE 指向未定义模板, 必须自建 MinimalScrollBar 并用 ScrollUtil 绑定
	local bar = CreateFrame("EventFrame", nil, scroll, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", BAR_X_TOP, BAR_DY_TOP)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", BAR_X_BOTTOM, BAR_DY_BOTTOM)
	bar:Show()
	ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(CONTENT_W) -- 首帧估计值, 真机由 OnSizeChanged / OnShow 校正
	scroll:SetScrollChild(content)

	-- 一切与宽度相关的几何都在这里落点: 尺寸变化即整份重排, 锚点先清后设
	local function Layout()
		local boxW = content:GetWidth() - BOX_INSET
		local colW = (boxW - BOX_PAD * 2) / 3
		for i = 1, #regions do
			local r = regions[i]
			r.box:SetWidth(boxW)
			local cbs = r.cbs
			for j = 1, #cbs do
				local item = cbs[j]
				local cb = item[1]
				cb:ClearAllPoints()
				cb:SetPoint("TOPLEFT", r.box, "TOPLEFT",
					BOX_PAD + item[2] * colW, -(BOX_PAD + item[3] * ROW_H))
			end
		end
	end

	local groups = {} -- 总开关 cfgKey -> 受其控制的子项

	local function addCheck(label, cfgKey, masterKey)
		local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
		cb.cfgKey = cfgKey
		cb.text:SetText(label)
		GrowFont(cb.text)
		cb.text:SetTextColor(1, 1, 1)
		cb:SetChecked(config.data[cfgKey])
		cb:SetScript("OnClick", function(button)
			local enabled = button:GetChecked()
			config:Set(cfgKey, enabled)
			local group = groups[cfgKey]
			if group then
				for i = 1, #group do
					if enabled then group[i]:Enable() else group[i]:Disable() end
				end
			end
			ns.engine:Refresh()
		end)
		if masterKey and not config.data[masterKey] then cb:Disable() end
		return cb
	end

	local prevBox
	local totalH = 4

	for i = 1, #REGIONS do
		local info = REGIONS[i]

		local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		header:SetText(info.title)
		GrowFont(header)
		header:SetTextColor(1, 0.82, 0)
		if prevBox then
			header:SetPoint("TOPLEFT", prevBox, "BOTTOMLEFT", LABEL_X, -REGION_GAP)
		else
			header:SetPoint("TOPLEFT", content, "TOPLEFT", LABEL_X, -4)
		end

		local box = CreateBox(content)
		box:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -LABEL_X, -HEADER_GAP)

		local masterKey = info.key .. "Enabled"
		local master = addCheck("启用头像增强", masterKey)
		local cbs = { { master, 0, 0 } }
		local group = {}
		groups[masterKey] = group

		local subs = info.subs
		for j = 1, #subs do
			local sub = SUBS[subs[j]]
			local cb = addCheck(sub[1], info.key .. sub[2], masterKey)
			cbs[#cbs + 1] = { cb, (j - 1) % 3, 1 + math.floor((j - 1) / 3) }
			group[#group + 1] = cb
		end

		-- 盒子高度自算: 勾选框锚盒子顶, 盒底若反向锚勾选框即成循环锚点
		local boxH = BOX_PAD * 2 + math.ceil(#subs / 3) * ROW_H + CB_H
		box:SetHeight(boxH)

		regions[#regions + 1] = { box = box, cbs = cbs, master = master, masterKey = masterKey, subs = group }
		prevBox = box
		totalH = totalH + HEADER_H + HEADER_GAP + boxH + REGION_GAP
	end

	content:SetHeight(totalH)

	scroll:SetScript("OnSizeChanged", function(_, w)
		if w > 0 then
			content:SetWidth(w)
			Layout()
		end
	end)

	panel:SetScript("OnShow", function()
		-- 填满 canvas 可视区: 外层不产生第二根滚动条, 滚动交给内嵌 scroll
		panel:ClearAllPoints()
		panel:SetAllPoints(panel:GetParent())
		local w = scroll:GetWidth()
		if w > 0 then content:SetWidth(w) end
		Layout()
		for i = 1, #regions do
			local r = regions[i]
			local enabled = config.data[r.masterKey]
			r.master:SetChecked(enabled)
			local subs = r.subs
			for j = 1, #subs do
				local cb = subs[j]
				cb:SetChecked(config.data[cb.cfgKey])
				if enabled then cb:Enable() else cb:Disable() end
			end
		end
	end)

	Layout()

	self.category = Settings.RegisterCanvasLayoutCategory(panel, ADDON_NAME)
	Settings.RegisterAddOnCategory(self.category)
end

function options:Open()
	Settings.OpenToCategory(self.category.ID)
end
