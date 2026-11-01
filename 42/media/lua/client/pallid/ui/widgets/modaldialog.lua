require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"
local normaliseButton = require "pallid/ui/widgets/modaldialog/button_spec"
local addButtonMethods = require "pallid/ui/widgets/modaldialog/buttons"
local addInputMethods = require "pallid/ui/widgets/modaldialog/input"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local I = Pallid.UI._internal

local BUTTON_H = 26
local BUTTON_GAP = 8
local BUTTON_PADDING = 10
local ICON = 14
local ICON_GAP = 6
local GAP = 8
local PADDING = 16
local TITLE_GAP = 8
local CONTENT_GAP = 12
local MIN_WIDTH = 320
local MIN_HEIGHT = 120
local ROUND = 6
local RECT_SHAPE = Pallid.UI.Shape.rect()
local ICON_DIR = "media/assets/ui/pallid/icons/"

--- Modal dialog: a centered panel on a dimmed backdrop that blocks input until
--- a button is pressed. Owned by the root (`root.modal`), drawn by the overlay.
--- @class PallidModalDialog : PallidWidget
--- @field title string Title text.
--- @field message string Message text.
--- @field buttons table[] Normalised button descriptors.
--- @field content PallidWidget|nil Optional interactive content.
--- @field autoSize boolean True recalculates height from title/message/buttons.
--- @field allowEscape boolean True lets Escape activate a negative button.
--- @field closeOnBackdrop boolean True closes when the dim backdrop is clicked.
local Modal = Widgets.class("ModalDialog")
addButtonMethods(Modal)
addInputMethods(Modal)

--- Creates a new `Modal` instance.
--- @param opts table|nil Dialog options.
--- @field opts.title string|nil Title text.
--- @field opts.message string|nil Message text.
--- @field opts.buttons table[]|nil Button descriptors.
--- @field opts.content PallidWidget|nil Optional content widget.
--- @field opts.width number|nil Dialog width in pixels.
--- @field opts.height number|nil Dialog height in pixels.
--- @field opts.autoSize boolean|nil True sizes the dialog to its contents.
--- @field opts.padding number|nil Inner padding in pixels.
--- @field opts.buttonHeight number|nil Dialog button height in pixels.
--- @field opts.buttonGap number|nil Gap between dialog buttons in pixels.
--- @field opts.buttonRadius number|nil Button corner radius, defaults to 4.
--- @field opts.allowEscape boolean|nil Defaults to true.
--- @field opts.closeOnBackdrop boolean|nil Defaults to false.
--- @field opts.sound string|false|nil Button click sound.
--- @field opts.onOpen fun(dialog: PallidModalDialog)|nil Called after the dialog opens.
--- @field opts.onClose fun(dialog: PallidModalDialog)|nil Called after the dialog closes.
--- @field opts.onResult fun(button: table, dialog: PallidModalDialog)|nil Called with the pressed button descriptor.
--- @return PallidModalDialog dialog The dialog instance.
function Modal.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Modal)
    self:init(0, 0, math.max(MIN_WIDTH, opts.width or 420), opts.height or 190)

    self.title = opts.title or "Confirm"
    self.message = opts.message or ""
    self.padding = math.max(0, opts.padding or PADDING)
    self.buttonHeight = math.max(12, opts.buttonHeight or BUTTON_H)
    self.buttonGap = math.max(0, opts.buttonGap or BUTTON_GAP)
    self.buttonRadius = math.max(0, opts.buttonRadius or 4)
    self.minButtonWidth = math.max(20, opts.minButtonWidth or 64)
    self.autoSize = opts.autoSize == true
    self.allowEscape = opts.allowEscape ~= false
    self.closeOnBackdrop = opts.closeOnBackdrop == true
    self.sound = opts.sound
    if self.sound == nil then
        self.sound = "UIActivateButton"
    elseif self.sound == false or self.sound == "" then
        self.sound = nil
    end
    self.onOpen = opts.onOpen
    self.onClose = opts.onClose
    self.onResult = opts.onResult
    self.content = nil
    self.contentHeight = math.max(0, opts.contentHeight or 100)
    self._contentDesired = 0
    self.root = nil
    self.visible = false
    self.hoverButton = 0
    self._capture = nil
    self._pressedButton = 0
    self._hovered = nil
    self._buttonRects = {}
    self._buttonsDirty = true

    self.dim = Pallid.UI.Color.overlay
    self.fill = Pallid.UI.Color.surfaceElevated
    self.borderColor = Pallid.UI.Color.border
    self.titleColor = Pallid.UI.Color.textPrimary
    self.textColor = Pallid.UI.Color.textMuted
    self.buttonFill = Pallid.UI.Color.surfaceMuted
    self.buttonHover = Pallid.UI.Color.accentSoft
    self.primaryFill = Pallid.UI.Color.primaryStrong
    self.primaryHover = Pallid.UI.Color.primary
    self.warningFill = Pallid.UI.Color.warning
    self.warningHover = Pallid.UI.Color.lerp(Pallid.UI.Color.warning, Pallid.UI.Color.textPrimary, 0.12)
    self.dangerFill = Pallid.UI.Color.error
    self.dangerHover = Pallid.UI.Color.lerp(Pallid.UI.Color.error, Pallid.UI.Color.textPrimary, 0.12)
    self.disabledFill = Pallid.UI.Color.surface
    self.disabledText = Pallid.UI.Color.textDisabled

    self.titleStyle = {
        font = Pallid.UI.Fonts.medium,
        color = self.titleColor,
        alignH = "left",
        alignV = "top",
        ellipsis = "...",
    }
    self.messageStyle = {
        font = Pallid.UI.Fonts.small,
        color = self.textColor,
        alignH = "left",
        alignV = "top",
        wrap = true,
        maxLines = opts.messageMaxLines or 4,
        ellipsis = "...",
    }
    self.buttonStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textPrimary,
        alignH = "center",
        alignV = "middle",
        ellipsis = "...",
    }

    self:setButtons(opts.buttons)
    if opts.content ~= nil then
        self:setContent(opts.content)
    end
    return self
end

--- Factory shortcut for `Modal.new`.
--- @param opts table|nil Dialog options; see `Modal.new`.
--- @return PallidModalDialog dialog The dialog instance.
function Widgets.modalDialog(opts)
    return Modal.new(opts)
end

--- Replaces the button list.
--- @param buttons table[]|nil New buttons; nil restores the default pair.
--- @return PallidModalDialog self For chaining.
function Modal:setButtons(buttons)
    if buttons == nil then
        buttons = {
            {
                text = I.translate("UI_Pallid_ModalCancel", "Cancel"),
                icon = ICON_DIR .. "cross.png",
                negative = true,
            },
            {
                text = I.translate("UI_Pallid_ModalOK", "OK"),
                icon = ICON_DIR .. "tick.png",
                primary = true,
            },
        }
    end
    self.buttons = {}
    for i = 1, #buttons do
        self.buttons[i] = normaliseButton(buttons[i])
    end
    self._buttonsDirty = true
    self.hoverButton = 0
    self._pressedButton = 0
    self:_createButtonWidgets()
    self:_layout()
    return self
end

--- Sets the title text.
--- @param title string New dialog title.
--- @return PallidModalDialog self For chaining.
function Modal:setTitle(title)
    self.title = title ~= nil and tostring(title) or ""
    self:_layout()
    return self
end

--- Sets the message text.
--- @param message string New dialog message.
--- @return PallidModalDialog self For chaining.
function Modal:setMessage(message)
    self.message = message ~= nil and tostring(message) or ""
    self:_layout()
    return self
end

--- Replaces the optional content widget.
--- @param content PallidWidget|nil New content, or nil to remove it.
--- @return PallidModalDialog self For chaining.
function Modal:setContent(content)
    if self.content ~= nil then
        self:remove(self.content)
    end
    self.content = content
    if content ~= nil then
        self:add(content)
        self._contentDesired = content.h > 0 and content.h or self.contentHeight
    else
        self._contentDesired = 0
    end
    self:_layout()
    return self
end

--- Replaces dialog colours.
--- @param colors table Keys: `dim`, `fill`, `border`, `title`, `text`, `buttonFill`, `buttonHover`, `primaryFill`, `primaryHover`, `warningFill`, `warningHover`, `dangerFill`, `dangerHover`, `disabledFill`, `disabledText`.
--- @return PallidModalDialog self For chaining.
function Modal:setColors(colors)
    colors = colors or {}
    if colors.dim ~= nil then
        self.dim = colors.dim
    end
    if colors.fill ~= nil then
        self.fill = colors.fill
    end
    if colors.border ~= nil then
        self.borderColor = colors.border
    end
    if colors.title ~= nil then
        self.titleColor = colors.title
        self.titleStyle.color = colors.title
    end
    if colors.text ~= nil then
        self.textColor = colors.text
        self.messageStyle.color = colors.text
    end
    if colors.buttonFill ~= nil then
        self.buttonFill = colors.buttonFill
    end
    if colors.buttonHover ~= nil then
        self.buttonHover = colors.buttonHover
    end
    if colors.primaryFill ~= nil then
        self.primaryFill = colors.primaryFill
    end
    if colors.primaryHover ~= nil then
        self.primaryHover = colors.primaryHover
    end
    if colors.warningFill ~= nil then
        self.warningFill = colors.warningFill
    end
    if colors.warningHover ~= nil then
        self.warningHover = colors.warningHover
    end
    if colors.dangerFill ~= nil then
        self.dangerFill = colors.dangerFill
    end
    if colors.dangerHover ~= nil then
        self.dangerHover = colors.dangerHover
    end
    if colors.disabledFill ~= nil then
        self.disabledFill = colors.disabledFill
    end
    if colors.disabledText ~= nil then
        self.disabledText = colors.disabledText
    end
    if self._buttonWidgets ~= nil then
        self:_createButtonWidgets()
        self:_layout()
    end
    return self
end

--- Changes the dialog size. Explicit sizing disables auto height.
--- @param w number New width.
--- @param h number New height.
--- @return PallidModalDialog self For chaining.
function Modal:setSize(w, h)
    self.w = math.max(80, w)
    self.h = math.max(60, h)
    self.autoSize = false
    self:_layout()
    return self
end

--- Measures the title and message with the current width.
--- @return number titleHeight Measured title height.
--- @return number messageHeight Measured message height.
function Modal:_measureTexts()
    self.titleStyle.maxWidth = math.max(0, self.w - self.padding * 2)
    self.messageStyle.maxWidth = math.max(0, self.w - self.padding * 2)
    local _, titleH = Pallid.UI.measureText(self.title, self.titleStyle)
    local _, messageH = Pallid.UI.measureText(self.message, self.messageStyle)
    return titleH, messageH
end

--- Recomputes message, content and button geometry.
function Modal:_layout()
    if self._rootW ~= nil then
        self.w = math.max(80, math.min(self.w, self._rootW - 8))
    end
    local titleH, messageH = self:_measureTexts()
    self._titleH = titleH
    self._messageH = messageH
    if self._buttonsDirty then
        self:_measureButtons()
    end

    local contentH = self.content ~= nil and (self._contentDesired or self.contentHeight) or 0
    local minH = self.padding + titleH + TITLE_GAP + messageH
        + (self.content ~= nil and (CONTENT_GAP + contentH) or 0)
        + GAP + self._buttonAreaH + self.padding
    if self.autoSize or self.h < minH then
        self.h = minH
    end
    if self._rootH ~= nil then
        self.h = math.max(60, math.min(self.h, self._rootH - 8))
    end

    self._messageY = self.padding + titleH + TITLE_GAP
    local contentY = self._messageY + messageH + CONTENT_GAP
    self._contentY = contentY
    self._buttonY = self.h - self.padding - self._buttonAreaH
    self._contentH = math.max(0, self._buttonY - GAP - contentY)
    if self.content ~= nil then
        self.content:setBounds(
            self.padding,
            contentY,
            math.max(0, self.w - self.padding * 2),
            self._contentH
        )
    end
    self:_layoutButtons()
end

--- Opens the dialog on a root.
--- @param root PallidWidget Root that owns the dialog.
--- @return PallidModalDialog self For chaining.
function Modal:open(root)
    if root == nil then
        Pallid.log("ModalDialog:open requires a root widget")
        return self
    end
    if root.modal ~= nil and root.modal ~= self then
        root.modal:close()
    end
    -- Any pre-existing overlay belongs to the page below the modal.
    if root.openMenu ~= nil then
        root.openMenu:close()
    end
    if root.openPopup ~= nil then
        root.openPopup:close()
    end
    if root.openPopover ~= nil then
        root.openPopover:close()
    end

    self.root = root
    self.parent = root
    self._rootW = root.w
    self._rootH = root.h
    self:_layout()
    self.x = math.floor(((root.w or 800) - self.w) * 0.5)
    self.y = math.floor(((root.h or 600) - self.h) * 0.5)
    self.x = math.max(0, math.min(self.x, math.max(0, root.w - self.w)))
    self.y = math.max(0, math.min(self.y, math.max(0, root.h - self.h)))
    self.visible = true
    self._ox = 0
    self._oy = 0
    self._capture = nil
    self._pressedButton = 0
    self._hovered = nil
    root.modal = self
    if self.onOpen ~= nil then
        self.onOpen(self)
    end
    return self
end

--- Returns true while the popup is open.
--- @return boolean open True while the dialog is visible.
function Modal:isOpen()
    return self.visible
end

--- Closes the dialog.
--- @return PallidModalDialog self For chaining.
function Modal:close()
    if not self.visible then
        return self
    end
    self.visible = false
    self._capture = nil
    self._pressedButton = 0
    self.hoverButton = 0
    self:setNativeVisible(false)
    self:blurNative()
    if self._hovered ~= nil then
        self._hovered._hover = false
        self._hovered:onHoverEnd()
        self._hovered = nil
    end
    local root = self.root
    if root ~= nil then
        if root.openMenu ~= nil then
            root.openMenu:close()
        end
        if root.openPopup ~= nil then
            root.openPopup:close()
        end
        if root.openPopover ~= nil then
            root.openPopover:close()
        end
        if root.focused ~= nil and self:_contains(root.focused) then
            root.focused:blur()
        end
        if root.modal == self then
            root.modal = nil
        end
    end
    if self.onClose ~= nil then
        self.onClose(self)
    end
    return self
end

--- Returns true when the widget is this dialog or one of its descendants.
--- @param widget PallidWidget Candidate descendant.
--- @return boolean contained True when widget belongs to this dialog.
function Modal:_contains(widget)
    local node = widget
    while node ~= nil do
        if node == self then
            return true
        end
        node = node.parent
    end
    return false
end

--- Returns the Y position of the message.
--- @return number x Message Y relative to the dialog.
function Modal:messageY()
    self:_layout()
    return self._messageY
end

--- Returns the message height.
--- @return number height Wrapped message height.
function Modal:messageHeight()
    local _, height = self:_measureTexts()
    return height
end

--- Returns the Y position of the content area.
--- @return number y Optional content Y relative to the dialog.
function Modal:contentY()
    self:_layout()
    return self._contentY
end

--- Plays the configured click sound.
function Modal:_playSound()
    if self.sound ~= nil and getSoundManager ~= nil then
        getSoundManager():playUISound(self.sound)
    end
end

--- Paints the modal shell and its contents.
--- @param el ISUIElement Host element.
--- @param ox number Parent origin X.
--- @param oy number Parent origin Y.
--- @param rootW number Root width.
--- @param rootH number Root height.
function Modal:drawModal(el, ox, oy, rootW, rootH)
    if not self.visible then
        return
    end
    Pallid.UI.rect(el, ox, oy, rootW, rootH, self.dim)
    self:draw(el, ox, oy)
end

--- Draws the dialog, clipped content and buttons. Buttons are painted after the
--- content so a child cannot cover them.
--- @param el ISUIElement Host element.
--- @param ox number Parent origin X.
--- @param oy number Parent origin Y.
function Modal:draw(el, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible then
        return
    end
    self:drawSelf(el)

    -- Only clip when there is content to clip. Pushing a stencil for a dialog
    -- without content left the clip active: buttons were culled and the leaked
    -- stencil rejected the next frame's rendering (black screen).
    if self.content ~= nil then
        local x, y = self:originX(), self:originY()
        local clipped = self._contentH > 0 and self._contentY ~= nil
            and Pallid.UI.clip(
                el,
                RECT_SHAPE,
                x + self.padding,
                y + self._contentY,
                math.max(0, self.w - self.padding * 2),
                self._contentH
            )
        self.content:draw(el, x, y)
        if clipped then
            Pallid.UI.clipEnd(el)
        end
    end
    self:_drawButtons(el)
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element.
function Modal:drawSelf(el)
    local x, y = self:originX(), self:originY()
    Pallid.UI.roundedRect(el, x, y, self.w, self.h, ROUND, self.fill)
    Pallid.UI.roundedBorder(el, x, y, self.w, self.h, ROUND, 1, self.borderColor)

    self.titleStyle.color = self.titleColor
    Pallid.UI.text(el, self.title, x + self.padding, y + self.padding, self.titleStyle)

    self.messageStyle.maxWidth = self.w - self.padding * 2
    Pallid.UI.text(el, self.message, x + self.padding, y + (self._messageY or 0), self.messageStyle)
end

