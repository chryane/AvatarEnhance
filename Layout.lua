--[[ Layout.lua - 徽章组件
	 自有子框架挂在单位框上: 可选外框 + 内容(职业/职责图集 或 等级文字), 按极坐标落在头像边缘;
	 逐项缓存上次状态, 未变化不产生 C 调用。
]]

local _, ns = ...
local media, config = ns.media, ns.config

-- frac = 占头像宽度比例; hole = 内容占外框直径比例
-- 小队(头像宽 37)的 frac 只算出 17.92 / 11.1 / 11.1, 实际尺寸由 min 定平: 职业 18、职责 14、等级 16
-- 玩家/目标/焦点走 frac: 职业被 max 截在 26, 职责 19.2
local KINDS = {
	class = { frac = 0.484375, min = 18, max = 26, hole = 0.6, bg = true, mask = true },
	role  = { frac = 0.30, min = 14, max = 26, hole = 1 },
	level = { frac = 0.30, min = 16, max = 26, bg = true, text = true },
}

local Badge = {}
Badge.__index = Badge
ns.Badge = Badge

-- 角度恒定(0=右, 90=上, 逆时针), 单位方向在此预计算
function Badge.new(parent, kind, angle)
	local spec = KINDS[kind]
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetFrameLevel(parent:GetFrameLevel() + 10)

	if spec.bg then
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetTexture(media.frameTexture)
		bg:SetAllPoints(frame)
	end

	local rad = angle * math.pi / 180
	local self = setmetatable({
		frame = frame,
		spec = spec,
		shown = false,
		ux = 0.5 * math.cos(rad),
		uy = 0.5 * math.sin(rad),
	}, Badge)

	if spec.text then
		self.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.label:SetTextColor(1, 0.82, 0)
	else
		local icon = frame:CreateTexture(nil, "ARTWORK")
		self.icon = icon
		if spec.mask then
			-- 遮罩 1:1 跟随图标(SetAllPoints), 换图/改大小都不用重挂
			local mask = frame:CreateMaskTexture(nil, "ARTWORK")
			mask:SetTexture(media.maskCircle, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(icon)
			icon:AddMaskTexture(mask)
		end
	end

	frame:Hide()
	return self
end

-- content 为 nil 即隐藏; anchor 定位基准; baseW 基准宽度
function Badge:Update(content, anchor, baseW)
	local frame = self.frame
	if not content then
		if self.shown then
			self.shown = false
			frame:Hide()
		end
		return
	end

	local spec = self.spec
	local size = math.min(math.max(baseW * spec.frac, spec.min), spec.max) * config.scale
	if size ~= self.size then
		self.size = size
		frame:SetSize(size, size)
		local label = self.label
		if label then
			-- 等级框 16 ⇒ 字号 10(跟随 config.scale, 所以写比例不写死)
			label:SetFont(label:GetFont(), size * 0.625, "OUTLINE")
			label:ClearAllPoints()
			-- OUTLINE 使可见笔画偏左下, 向右上补偿
			label:SetPoint("CENTER", frame, "CENTER", size * 0.06, size * 0.06)
		end
	end

	local icon = self.icon
	if icon then
		local iconSize = size * spec.hole
		if content ~= self.content then
			self.content = content
			icon:SetAtlas(content) -- 先 atlas 再设宽高: SetAtlas 会重置尺寸
			icon:ClearAllPoints()  -- 清掉默认四角锚点, 宽高才生效
			icon:SetPoint("CENTER", frame, "CENTER")
			self.iconSize = iconSize
			icon:SetSize(iconSize, iconSize)
		elseif iconSize ~= self.iconSize then
			self.iconSize = iconSize
			icon:SetSize(iconSize, iconSize)
		end
	elseif content ~= self.content then
		self.content = content
		self.label:SetText(content)
	end

	-- 位置只由 anchor 与 baseW 决定(config.scale 只改尺寸)
	if anchor ~= self.anchor or baseW ~= self.baseW then
		self.anchor, self.baseW = anchor, baseW
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", anchor, "CENTER", baseW * self.ux, baseW * self.uy)
	end

	if not self.shown then
		self.shown = true
		frame:Show()
	end
end

-- .portrait 由 UnitFrame_Initialize 统一赋值, 四类框都有; 全局名只作兜底(玩家框那份叫 PlayerPortrait)
-- 宽度校验防止锚到尺寸异常的容器
function ns.FindPortrait(frame, portraitName)
	local p = frame.portrait
	if p and p:GetWidth() > 0 then return p end
	p = _G[portraitName]
	if p and p:GetWidth() > 0 then return p end
end
