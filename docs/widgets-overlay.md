# Pallid overlay widgets

Dialogs, tooltips, notifications, popups and menus that are painted above the widget tree by the root's overlay pass.
All factories live on `Pallid.UI.Widgets` and every overlay is attached to a root widget, never to a page child. The host and widget-tree APIs are documented in [ui-host.md](ui-host.md) and [ui-widget.md](ui-widget.md).

```lua
-- Every example below assumes a root widget that is already rendered:
local host = Pallid.UI.Host:new()
local page = Pallid.UI.Widgets.panel(0, 0, 800, 600, {})
host:setRoot(page)
host:addToUIManager()
local root = page -- the root widget; overlays attach to it
```

## ModalDialog

Creates a centered, input-blocking dialog on a dimmed backdrop. Only one modal can be open per root; the root owns it as `root.modal` and paints it after the tree.

**Side:** client

### Parameters

Factory: `Pallid.UI.Widgets.modalDialog(opts)`

- opts (table|nil) - Dialog options; every field below is optional.
- opts.title (string|nil) - Title text. Defaults to `"Confirm"`.
- opts.message (string|nil) - Wrapped body text. Defaults to `""`.
- opts.buttons (table[]|nil) - Button descriptors; `nil` restores the default Cancel/OK pair.
- opts.content (PallidWidget|nil) - Interactive widget added inside the dialog body.
- opts.width (number|nil) - Dialog width in pixels. Defaults to `420` and is raised to at least `320`.
- opts.height (number|nil) - Initial height in pixels. Defaults to `190`; the layout grows it to fit the content.
- opts.autoSize (boolean|nil) - `true` recalculates the height on every layout. Defaults to `false`; a non-auto-sized dialog still grows when the content needs more room and never shrinks back.
- opts.padding (number|nil) - Inner padding in pixels. Defaults to `16`.
- opts.buttonHeight (number|nil) - Dialog button height. Defaults to `26`, minimum `12`.
- opts.buttonGap (number|nil) - Gap between buttons and between button rows. Defaults to `8`.
- opts.buttonRadius (number|nil) - Button corner radius. Defaults to `4`.
- opts.minButtonWidth (number|nil) - Smallest button width. Defaults to `64`.
- opts.contentHeight (number|nil) - Height used when the content widget has no height of its own. Defaults to `100`.
- opts.messageMaxLines (number|nil) - Maximum wrapped message lines before ellipsis. Defaults to `4`.
- opts.allowEscape (boolean|nil) - `true` lets Escape activate a negative button. Defaults to `true`.
- opts.closeOnBackdrop (boolean|nil) - `true` closes the dialog when the dim backdrop is left-clicked. Defaults to `false`.
- opts.sound (string|false|nil) - Button click sound. Defaults to `"UIActivateButton"`; `false` or `""` silences it.
- opts.onOpen (fun(dialog: PallidModalDialog)|nil) - Called after the dialog opens.
- opts.onClose (fun(dialog: PallidModalDialog)|nil) - Called after the dialog closes.
- opts.onResult (fun(button: table, dialog: PallidModalDialog)|nil) - Called with the pressed button descriptor.

### Returns

- PallidModalDialog - Dialog instance (`Pallid.UI.Widgets.ModalDialog`).

### Methods
- `open(root) -> self` - Opens the dialog on the given root widget.
- `close() -> self` - Closes the dialog and clears the root modal.
- `isOpen() -> boolean` - True while the dialog is visible.
- `setTitle(title) -> self` - Replaces the title text.
- `setMessage(message) -> self` - Replaces the wrapped body text.
- `setButtons(buttons) -> self` - Replaces the button list; `nil` restores the default pair.
- `setContent(content) -> self` - Swaps the body widget; `nil` removes it.
- `setSize(w, h) -> self` - Resizes the dialog and turns `autoSize` off.
- `setColors(colors) -> self` - Replaces the dialog palette.
- `buttonRect(index) -> x, y, w, h` - Root-local rectangle of one button.
- `messageY() -> number` - Message Y offset inside the dialog.
- `messageHeight() -> number` - Wrapped message height in pixels.
- `contentY() -> number` - Content area Y offset inside the dialog.

### Example

```lua
local dialog = Pallid.UI.Widgets.modalDialog({
    title = "Delete save?",
    message = "This cannot be undone.",
    buttons = {
        { text = "Cancel", negative = true },
        { text = "Delete", danger = true, positive = true },
    },
    onResult = function(button)
        if button.positive then
            -- delete
        end
    end,
})
dialog:open(root)
```

### Notes

- `open(root)` requires the tree root, not an arbitrary child. It sets `root.modal`, closes any menu, popup or popover already open on that root, and centers the dialog inside the root.
- `close()` clears `root.modal`, blurs native inputs inside the dialog and fires `onClose`. It does not fire `onResult`.
- Enter activates the positive/primary button. Escape activates the negative button when `allowEscape` is true, and closes the dialog when no negative button exists. With `allowEscape = false`, Escape is ignored unless a menu, popup or popover is open on the root.
- Button descriptor fields: `text` (falls back to `label`), `icon`, `primary`, `positive`, `negative`, `cancel` (alias of `negative`), `danger`, `disabled`, `closeOnClick` (defaults to `true`) and `onClick(button, dialog)`. `onResult` fires even when `closeOnClick` is `false`.
- `setButtons(buttons)` replaces the list, `setContent(content)` swaps the body widget, `setTitle`, `setMessage`, `setSize(w, h)` and `setColors(colors)` update a live dialog. `setSize` turns `autoSize` off.
- `setColors` accepts `dim`, `fill`, `border`, `title`, `text`, `buttonFill`, `buttonHover`, `primaryFill`, `primaryHover`, `warningFill`, `warningHover`, `dangerFill`, `dangerHover`, `disabledFill` and `disabledText`.
- The content widget is clipped to the body area when that area has height; buttons are always painted after it.

## ConfirmDialog

Wraps `modalDialog` with a fixed cancel/confirm pair and forwards the outcome to one of two callbacks.

**Side:** client

### Parameters

Factory: `Pallid.UI.Widgets.confirmDialog(opts)`

- opts (table|nil) - Dialog content and callbacks.
- opts.title (string|nil) - Title. Defaults to the translated `"Confirm"`.
- opts.message (string|nil) - Body text. Defaults to `""`.
- opts.confirmText (string|nil) - Positive button text. Defaults to `"OK"`.
- opts.cancelText (string|nil) - Negative button text. Defaults to `"Cancel"`.
- opts.danger (boolean|nil) - Styles the positive button with the danger palette. Defaults to `false`.
- opts.width (number|nil) - Dialog width; the modal default applies when omitted.
- opts.autoSize (boolean|nil) - Sizes the dialog to its content. Defaults to `true`.
- opts.onConfirm (fun(confirm: PallidConfirmDialog)|nil) - Called when the positive button is pressed.
- opts.onCancel (fun(confirm: PallidConfirmDialog)|nil) - Called for the negative button or Escape.

### Returns

- PallidConfirmDialog - Wrapper with a `dialog` field holding the underlying modal.

### Methods
- `open(root) -> self` - Opens the wrapped modal on the given root widget.
- `close() -> self` - Closes the wrapped modal without firing a callback.
- `isOpen() -> boolean` - True while the wrapped modal is visible.

### Example

```lua
local confirm = Pallid.UI.Widgets.confirmDialog({
    title = "Quit to menu?",
    message = "Unsaved progress is lost.",
    confirmText = "Quit",
    danger = true,
    onConfirm = function()
        -- quit
    end,
    onCancel = function()
        -- stay
    end,
})
confirm:open(root)
```

### Notes

- `open(root)`, `close()` and `isOpen()` delegate to the wrapped modal. `close()` closes silently and fires neither callback.
- The dialog is always built with the same two buttons; use `confirm.dialog:setButtons(...)` if a different layout is required.
- There are no title/message setters on the wrapper; call `confirm.dialog:setTitle(...)` or `confirm.dialog:setMessage(...)`.

## PromptDialog

Modal with a single text field, confirm/cancel buttons and optional validation that keeps the dialog open.

**Side:** client

### Parameters

Factory: `Pallid.UI.Widgets.promptDialog(opts)`

- opts (table|nil) - Prompt content and callbacks.
- opts.title (string|nil) - Title. Defaults to the translated `"Prompt"`.
- opts.message (string|nil) - Body text. Defaults to `""`.
- opts.value (string|nil) - Initial field text. Defaults to `""`.
- opts.placeholder (string|nil) - Field placeholder shown while empty.
- opts.masked (boolean|nil) - Masks the field as a password. Defaults to `false`.
- opts.confirmText (string|nil) - Positive button text. Defaults to `"OK"`.
- opts.cancelText (string|nil) - Negative button text. Defaults to `"Cancel"`.
- opts.width (number|nil) - Dialog width. Defaults to `420`; the field is sized from it.
- opts.validate (fun(value: string): boolean,string|nil) - Validator; returning anything other than `true` rejects the submit, and an optional second return is shown as the placeholder.
- opts.onSubmit (fun(prompt: PallidPromptDialog, value: string)|nil) - Called with a valid value.
- opts.onCancel (fun(prompt: PallidPromptDialog)|nil) - Called when the negative button is pressed.

### Returns

- PallidPromptDialog - Wrapper with `dialog` (the modal) and `input` (the text field).

### Methods
- `open(root) -> self` - Opens the modal and focuses the field.
- `close() -> self` - Closes the modal without firing a callback.
- `isOpen() -> boolean` - True while the modal is visible.
- `getValue() -> string` - Current field text.
- `setValue(value) -> self` - Replaces the field text silently.

### Example

```lua
local prompt = Pallid.UI.Widgets.promptDialog({
    title = "Rename character",
    value = "Brov3r",
    validate = function(value)
        if value == "" then
            return false, "Name cannot be empty"
        end
        return true
    end,
    onSubmit = function(_, value)
        -- use value
    end,
})
prompt:open(root)
```

### Notes

- The dialog is always auto-sized and the field is 26 px tall.
- A rejected value keeps the dialog open, turns the field border red and, when the validator returns a non-empty string, shows it as the placeholder.
- Enter inside the field submits; the confirm button also submits without closing first.
- `open(root)` resets the submit guard, restores the placeholder and border, opens the modal and focuses the field.
- `getValue()` returns the field text and `setValue(value)` replaces it.
- `close()` closes silently; `onCancel` fires for the negative button, including Escape.

## Tooltip

Hover tooltip with a fade-in/slide, an optional rich body (title, rows, sections, separators, footer) and a fade-out. It is attached to a widget with `Widget:setTooltip` and painted by the root on an always-on-top native surface.

**Side:** client

### Parameters

Factory: `Pallid.UI.Widgets.Tooltip.new(text, delay)`

- text (string|nil) - Plain body text; may contain `\n`. Defaults to `""`.
- delay (number|nil) - Seconds before the fade starts. Defaults to `0.12`; negative values become `0`.

Constructor fields that can be changed directly or through setters:

- title (string) - Bold line above the body. Defaults to `""`.
- rows (PallidTooltipRow[]) - Rich rows in draw order. Defaults to `{}`.
- footer (string) - Muted text below a divider. Defaults to `""`.
- maxWidth (number) - Width cap including padding. Defaults to `280`.
- maxLines (integer) - Maximum wrapped plain-body lines. Defaults to `8`.

### Returns

- PallidTooltip - Tooltip instance (`Pallid.UI.Widgets.Tooltip`).

### Methods
- `setText(text) -> self` - Replaces the plain body text.
- `setTitle(title) -> self` - Sets or removes the bold title.
- `setRows(rows) -> self` - Replaces every rich row; rows are copied.
- `addRow(row) -> self` - Appends one rich row.
- `setFooter(footer) -> self` - Sets or removes the footer text.
- `setMaxWidth(width) -> self` - Sets the width cap, at least `60`.
- `setMaxLines(lines) -> self` - Sets the wrapped plain-body line limit, at least `1`.
- `show(now) -> self` - Starts the fade-in; safe to call every frame while hovered.
- `beginClose(now) -> self` - Starts the fade-out; repeated calls are ignored.
- `reset() -> self` - Hides the tooltip but keeps its content.
- `clear() -> self` - Hides the tooltip and drops its content after the fade-out.
- `hasContent() -> boolean` - True when there is a title, body, row or footer to paint.
- `isEmpty() -> boolean` - True when the tooltip has no content.
- `isClosed() -> boolean` - True once the fade-out has finished.

### Example

```lua
local tip = Pallid.UI.Widgets.Tooltip.new("")
tip:setTitle("Fire Axe")
tip:setRows({
    { section = "Combat" },
    { icon = "media/assets/ui/pallid/icons/tick.png", label = "Damage", value = "1.8" },
    { swatch = Pallid.UI.Color.warning, label = "Weight", value = "4.0" },
    { separator = true },
    { label = "Condition", value = "82%" },
})
tip:setFooter("Right click to equip.")

local button = Pallid.UI.Widgets.button(0, 0, 160, 26, { text = "Fire Axe" })
button:setTooltip(tip)
page:add(button)
```

### Notes

- There is no `Widgets.tooltip` factory; use `Widgets.Tooltip.new`.
- Attach with `widget:setTooltip(tooltip)` or `widget:setTooltip("plain text", delay)`. No manual `show` is needed: the root calls it for the hovered widget.
- Row shape: `icon` (registered name, texture path, or `false` for none), `swatch` (PallidColor), `label`, `value` (string or number, right-aligned), `labelColor`, `valueColor`, `section` (heading text, or `true` to use `label`), `separator` (`true` draws a divider above the row). `icon` wins over `swatch` when both are set.
- `setRows` and `addRow` copy their input; the caller may reuse the table.
- `setText("")` hides a plain tooltip, but only removes the body when rich content exists. Use `clear()` to hide a rich tooltip; `clear()` drops the content after the fade-out.
- `setMaxWidth(width)` clamps to at least `60` and defaults to `280`. `setMaxLines(lines)` clamps to at least `1`.
- Passing a string to `setTooltip` after a rich tooltip clears the title, rows and footer and switches the widget back to plain text.
- `show(now)`, `beginClose(now)` and `reset()` are safe to call repeatedly; the hover lifecycle normally drives them. `hasContent()`, `isEmpty()` and `isClosed()` are read-only getters.

## Toast

Short self-dismissing notification anchored to a screen corner. Toasts stack per corner and per root, fade in, slide into their slot and show a lifetime track.

**Side:** client

### Parameters

Factory: `Pallid.UI.Widgets.toast(text, opts)`

- text (string|nil) - Notification body. Defaults to `""`; wrapped to at most three lines.
- opts (table|nil) - Appearance and timing overrides.
- opts.title (string|nil) - Bold first line; empty hides it.
- opts.duration (number|nil) - Seconds fully visible. Defaults to `3`; `0` disables the lifetime track.
- opts.width (number|nil) - Fixed width; when omitted the text is measured up to `360`.
- opts.height (number|nil) - Fixed height; when omitted it is measured.
- opts.margin (number|nil) - Distance from the screen edges. Defaults to `18`.
- opts.corner (string|nil) - `"top-right"`, `"top-left"`, `"bottom-right"` or `"bottom-left"`. Defaults to `"top-right"`; unknown values fall back to it.
- opts.background (PallidColor|nil) - Panel fill. Defaults to the elevated surface token.
- opts.border (PallidColor|nil) - Panel border. Defaults to the border token.
- opts.textColor (PallidColor|nil) - Body colour. Defaults to muted when a title is set, otherwise primary.
- opts.titleColor (PallidColor|nil) - Title colour. Defaults to primary text.
- opts.accent (PallidColor|nil) - Icon and lifetime-track colour. Defaults to the primary accent.
- opts.icon (string|nil) - Registered icon name or a texture path.
- opts.iconSize (number|nil) - Icon box in pixels. Defaults to `18`.
- opts.iconColor (PallidColor|nil) - Icon tint. Defaults to the accent.
- opts.showProgress (boolean|nil) - Draws the bottom lifetime track. Defaults to `true`.
- opts.font (UIFont|string|nil) - Body font. Defaults to the small font.

### Returns

- PallidToast - Hidden toast (`Pallid.UI.Widgets.Toast`); call `show` to display it.

### Methods
- `show(root, text, opts) -> self` - Attaches the toast to the root and starts its lifetime.
- `close() -> self` - Dismisses the toast immediately and promotes the next queued one.
- `setText(text) -> self` - Replaces the body and reflows a visible toast.
- `setTitle(title) -> self` - Replaces the bold title; empty hides it.
- `setIcon(icon) -> self` - Replaces the icon; `nil` removes it.
- `setAccent(color) -> self` - Replaces the icon and lifetime-track colour.

### Example

```lua
local toast = Pallid.UI.Widgets.toast("Inventory full.", {
    title = "Warning",
    corner = "bottom-right",
    icon = "media/assets/ui/pallid/icons/info.png",
    accent = Pallid.UI.Color.warning,
    duration = 4,
})
toast:show(root)
```

### Notes

- `show(root, text, opts)` attaches the toast to the root. `opts` is only read for `title` and `corner`; duration, size and colours stay as constructed.
- At most `Pallid.UI.Widgets.Toast.MAX_VISIBLE` (10) toasts are visible per root. Extra toasts wait in a queue and slide in when older ones finish; each corner owns an independent stack.
- Calling `show` again on a visible toast restarts its timer without replaying the fade-in.
- The toast is added to the root's child list when it becomes visible; it is not hittable, so it never steals hover from the widget underneath.
- `close()` dismisses it immediately and promotes the next queued toast.
- `setText`, `setTitle` and `setIcon` re-measure a visible toast and reflow its stack; `setAccent` only changes the colour.

## Popover

Small floating panel anchored to another widget. It is drawn above the tree and closed by an outside click.

**Side:** client

### Parameters

Factory: `Pallid.UI.Widgets.popover(content, opts)`

- content (PallidWidget|nil) - Content widget added as a child and resized to the padded area.
- opts (table|nil) - Appearance and behaviour.
- opts.width (number|nil) - Panel width. Defaults to `220`.
- opts.height (number|nil) - Panel height. Defaults to `120`.
- opts.padding (number|nil) - Content inset. Defaults to `8`.
- opts.offset (number|nil) - Gap from the anchor. Defaults to `6`.
- opts.background (PallidColor|nil) - Panel fill. Defaults to the elevated surface token.
- opts.border (PallidColor|nil) - Panel border. Defaults to the border token.
- opts.radius (number|nil) - Corner radius. Defaults to `6`.
- opts.clipChildren (boolean|nil) - `false` lets content paint outside the panel. Defaults to `true`.
- opts.onOpen (fun(popover: PallidPopover)|nil) - Called after opening.
- opts.onClose (fun(popover: PallidPopover)|nil) - Called after closing.

### Returns

- PallidPopover - Popover instance (`Pallid.UI.Widgets.Popover`, a `PallidPanel`).

### Methods
- `show(anchor, side) -> self` - Opens the popover next to an attached anchor widget.
- `showAt(root, x, y) -> self` - Opens the popover at root-local coordinates without an anchor.
- `close() -> self` - Closes the popover and fires the close callbacks.
- `isOpen() -> boolean` - True while the popover is visible.
- `reposition() -> self` - Recomputes the placement from the current anchor.
- `setContent(content) -> self` - Replaces the content widget; `nil` removes it.
- `setSize(w, h) -> self` - Resizes the panel and its content.

### Example

```lua
local content = Pallid.UI.Widgets.panel(0, 0, 0, 0, {})
content:add(Pallid.UI.Widgets.label("Anchored content", 0, 0, 200, 18, {}))

local anchorButton = Pallid.UI.Widgets.button(8, 8, 120, 26, { text = "Anchor" })
page:add(anchorButton)

local popover = Pallid.UI.Widgets.popover(content, { width = 220, height = 96 })
popover:show(anchorButton, "bottom")
```

### Notes

- `show(anchor, side)` requires an anchor that is already attached to a root (`anchor:getRoot()`). The popover attaches itself to that root as `root.openPopover`.
- `side` accepts `"bottom"`, `"top"`, `"left"`, `"right"` or `"auto"`. `"auto"` picks bottom when it fits, otherwise top; the chosen side is stored in `popover.side`.
- The panel is clamped 4 px inside the root. `showAt(root, x, y)` opens it at root-local coordinates without an anchor.
- Only one popover can be open per root; opening another closes the previous one.
- `update` closes the popover automatically when its anchor becomes invisible or leaves the root.
- `reposition()` recomputes the placement from the current anchor; `setContent`, `setSize(w, h)` and `setBounds(x, y, w, h)` resize the content.
- `close()` also calls `content.onClose()` when the content defines it, then `opts.onClose`.

## Menu

Vertical dropdown menu shown as an overlay at root-local coordinates. It supports separators, icons, shortcuts, submenus and checkable items.

**Side:** client

### Parameters

Factory: `Pallid.UI.Widgets.menu(items, opts)`

- items ((string|table)[]) - Menu items; a bare string becomes a label.
- opts (table|nil) - Appearance and behaviour.
- opts.minWidth (number|nil) - Minimum width. Defaults to `160`.
- opts.maxWidth (number|nil) - Maximum width. Defaults to `360`.
- opts.maxHeight (number|nil) - Maximum height before scrolling. Defaults to `320`.
- opts.itemHeight (number|nil) - Row height. Defaults to `22`, minimum `12`.
- opts.separatorHeight (number|nil) - Height of a separator row. Defaults to `9`.
- opts.padding (number|nil) - Menu padding. Defaults to `4`.
- opts.iconSize (number|nil) - Icon box. Defaults to `14`.
- opts.arrowSize (number|nil) - Submenu arrow size. Defaults to `9`.
- opts.gap (number|nil) - Gap between slots and text. Defaults to `6`.
- opts.submenuOffset (number|nil) - Horizontal gap to a submenu. Defaults to `5`.
- opts.font (UIFont|string|nil) - Item font or a `Pallid.UI.Fonts` key.
- opts.checkable (boolean|nil) - `true` toggles `item.checked` when a leaf item is clicked. Defaults to `false`.
- opts.reserveCheckSlot (boolean|nil) - Keeps the tick column even when nothing is checked. Defaults to `checkable`.
- opts.onCheck (fun(menu: PallidMenu, index: integer, checked: boolean, item: PallidMenuItem)|nil) - Called after a checkable item toggles.
- opts.closeOnSelect (boolean|nil) - `false` keeps the menu open after an action. Defaults to `true`, or `false` when `checkable` is set.
- opts.passThroughOutside (boolean|nil) - `true` lets an outside left click close the menu and continue to the widget below. Defaults to `false`.
- opts.onOpen (fun(menu: PallidMenu)|nil) - Called after the menu is shown.
- opts.onClose (fun(menu: PallidMenu)|nil) - Called after the menu or a submenu closes.
- opts.sound (string|false|nil) - Click sound. Defaults to `"UISelectListItem"`; `false` or `""` silences it.
- opts.background, opts.border, opts.hover, opts.separator, opts.text, opts.disabled, opts.shortcut, opts.danger, opts.check (PallidColor|nil) - Palette overrides.

### Returns

- PallidMenu - Menu instance (`Pallid.UI.Widgets.Menu`).

### Methods
- `show(root, x, y) -> self` - Opens the menu at root-local coordinates.
- `close() -> self` - Closes this menu and every open submenu.
- `closeChain() -> self` - Closes the whole chain, including the top-level menu.
- `openAt(index) -> PallidMenu|nil` - Opens the submenu of one item and returns it.
- `setItems(items) -> self` - Replaces every item and clears the hover state.
- `setColors(colors) -> self` - Replaces the menu palette.
- `setFont(font) -> self` - Replaces the item font.
- `isChecked(index) -> boolean` - True when the item is checked.
- `getChecked() -> integer[]` - Every checked item index in ascending order.
- `setChecked(index, checked, silent) -> self` - Changes one check state; `silent` skips `onCheck`.
- `isInside(px, py) -> boolean` - True when the point lies inside the menu.

### Example

```lua
local menu = Pallid.UI.Widgets.menu({
    { label = "Open", shortcut = "Ctrl+O", onClick = function(item) end },
    { separator = true },
    { label = "Read only", checked = true, checkable = true },
    { label = "Delete", danger = true, disabled = true },
}, {
    minWidth = 180,
    checkable = true,
})
menu:show(root, 120, 80)
```

### Item shape

- `label` (string) - Visible text; falls back to `text`.
- `icon` (string|Texture|nil) - Leading icon: registered name, texture path, or a Texture.
- `iconRight` (string|Texture|nil) - Icon before the shortcut.
- `shortcut` (string|nil) - Right-aligned shortcut text.
- `submenu` (table[]|nil) - Child items opened as a submenu.
- `onClick` (fun(item: PallidMenuItem, menu: PallidWidget)|nil) - Called when the item is activated.
- `separator` (boolean) - Draws a divider instead of a row.
- `disabled` (boolean) - Rejects clicks and submenu activation.
- `checked` (boolean) - Draws the tick.
- `checkable` (boolean) - Toggles when the menu is checkable; implied when `checked` is present.
- `danger` (boolean) - Uses the danger palette.
- `color`, `iconColor` (PallidColor|nil) - Per-item overrides.

### Notes

- `show(root, x, y)` attaches the menu to `root.openMenu`; a left click outside closes it, a right click outside closes it and continues to the widget under the cursor.
- Submenus open on hover and are drawn as part of the same overlay chain; `closeChain()` also closes the top-level menu that owns this submenu, while `close()` closes this menu and its open submenus.
- `setItems(items)` replaces the list, clears the hover state and invalidates cached submenus. `nil` clears the menu.
- `isChecked(index)`, `getChecked()` and `setChecked(index, checked, silent)` read and change check state. `silent` skips `onCheck`.
- `setColors(colors)` and `setFont(font)` update a live menu.
- `openAt(index)` opens the submenu of one item and returns it, or `nil` when the item has no submenu.

## MenuBar

Persistent horizontal menu bar that lives in the widget tree. Top-level items run an action or open a vertical `Menu` dropdown.

**Side:** client

### Parameters

Factory: `Pallid.UI.Widgets.menuBar(x, y, items, opts)`

- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- items ((string|table)[]) - Top-level items using the same shape as `menu`.
- opts (table|nil) - Appearance and behaviour.
- opts.height (number|nil) - Bar height. Defaults to `26`.
- opts.font (UIFont|string|nil) - Font or a `Pallid.UI.Fonts` key.
- opts.checkedMenu (boolean|nil) - Reserves a check slot for top-level items. Defaults to `false`.
- opts.submenuOffset (number|nil) - Gap from a dropdown to its submenu. Defaults to `5`.
- opts.iconSize (number|nil) - Item icon box. Defaults to `14`.
- opts.gap (number|nil) - Gap between item slots and text. Defaults to `6`.
- opts.arrowSize (number|nil) - Dropdown arrow size. Defaults to `9`.
- opts.background (PallidColor|nil) - Bar fill. Defaults to the muted surface token.
- opts.border (PallidColor|nil) - Bar border. Defaults to the border token.
- opts.hover (PallidColor|nil) - Hovered item fill.
- opts.active (PallidColor|nil) - Fill of the item whose dropdown is open.
- opts.text (PallidColor|nil) - Item text colour.
- opts.disabled (PallidColor|nil) - Disabled item colour.
- opts.danger (PallidColor|nil) - Danger item colour.
- opts.sound (string|false|nil) - Click sound. Defaults to `"UIActivateTab"`; `false` or `""` silences it.

### Returns

- PallidMenuBar - Menu bar widget (`Pallid.UI.Widgets.MenuBar`).

### Methods
- `openAt(index) -> PallidMenu|nil` - Opens the dropdown of one item and returns it.
- `closeDropdown() -> self` - Closes the current dropdown, if any.
- `setItems(items) -> self` - Replaces the top-level items and closes the dropdown.
- `setFont(font) -> self` - Replaces the bar font.
- `setColors(colors) -> self` - Replaces the bar palette.
- `itemRect(index) -> x, y, w, h` - Root-local rectangle of one top-level item.
- `itemAt(px, py) -> integer` - Item index under the point, or `0`.

### Example

```lua
local bar = Pallid.UI.Widgets.menuBar(8, 8, {
    {
        label = "File",
        submenu = {
            { label = "New", shortcut = "Ctrl+N", onClick = function() end },
            { label = "Open", shortcut = "Ctrl+O", onClick = function() end },
        },
    },
    { label = "View", onClick = function() end },
}, { height = 26 })
page:add(bar)
```

### Notes

- The bar is a normal tree widget: add it to a container with `parent:add(bar)`. Its dropdown is a `Menu` overlay attached to the root.
- A top-level item with `submenu` opens a dropdown on press; an item without a submenu fires `onClick` on release inside the item.
- Clicking the active top-level item again closes its dropdown. `closeDropdown()` closes it explicitly.
- The dropdown is marked checkable when any child has `checked ~= nil` or `checkable == true`; checkable dropdowns keep `closeOnSelect = true` so a choice closes them.
- `setItems(items)` replaces the items and closes the dropdown; `setFont`, `setColors`, `setEnabled` update the bar. Disabling the bar also closes the dropdown.
- `openAt(index)` opens the dropdown of one item and returns the `Menu`, or `nil` when the item has no submenu or is disabled.

## ContextMenu

Right-click menu built on the vertical `Menu` layout. It is the same widget as `menu` plus an `isContextMenu` marker field.

**Side:** client

### Parameters

Factory: `Pallid.UI.Widgets.contextMenu(items, opts)`

- items ((string|table)[]) - Menu items; same shape as `menu`.
- opts (table|nil) - Same options as `menu`.

### Returns

- PallidContextMenu - Context menu (`Pallid.UI.Widgets.ContextMenu`, a `PallidMenu`).

### Methods
- No methods of its own; `show`, `setItems`, `close`, `closeChain`, `openAt` and the rest are inherited from [menu](#menu).

### Example

```lua
local rowMenu = Pallid.UI.Widgets.contextMenu({}, { minWidth = 190 })
rowMenu:setItems({
    { label = "Edit", onClick = function(item) end },
    { label = "Duplicate", onClick = function(item) end },
    { separator = true },
    { label = "Delete", danger = true, onClick = function(item) end },
})
rowMenu:show(root, x, y) -- x, y from the right-click handler
```

### Notes

- `show(root, x, y)`, `setItems`, `close`, `closeChain` and the other methods are inherited from `menu`.
- A left click outside closes it. A right click outside also closes it and continues routing, so a context menu can open on the row under the cursor in the same press.
- `isContextMenu` is set to `true` by the constructor; no framework code currently reads it.

## RadialMenu

Radial command menu drawn around a center point, with sectors, icons, labels and a center caption. Selection happens on release.

**Side:** client

### Parameters

Factory: `Pallid.UI.Widgets.radialMenu(sectors, opts)`

- sectors (table[]|nil) - Sector descriptors; see the sector shape below.
- opts (table|nil) - Menu options.
- opts.innerRadius (number|nil) - Radius of the center hub. Defaults to `38`.
- opts.outerRadius (number|nil) - Outer radius of the ring. Defaults to `108`.
- opts.gap (number|nil) - Empty wedge between sectors, in radians. Defaults to `0.035`; capped at half a step.
- opts.background (PallidColor|nil) - Disc behind the sectors, also visible in the gaps.
- opts.sector (PallidColor|nil) - Default sector fill.
- opts.hover (PallidColor|nil) - Default hover fill.
- opts.labelColor (PallidColor|nil) - Sector label and icon tint.
- opts.centerColor (PallidColor|nil) - Center disc fill.
- opts.title (string|nil) - Center caption.
- opts.hint (string|nil) - Fallback caption under the title; the hovered sector label replaces it.
- opts.font (UIFont|string|nil) - Sector label font.
- opts.titleFont (UIFont|string|nil) - Center caption font. Defaults to the medium font.
- opts.iconSize (number|nil) - Sector icon box. Defaults to `20`; clamped to the ring width.
- opts.sound (string|false|nil) - Click sound. Defaults to `"UIActivateButton"`; `false` or `""` silences it.
- opts.onSelect (fun(radial: PallidRadialMenu, index: integer, sector: table)|nil) - Called after a sector is chosen.
- opts.onClose (fun(radial: PallidRadialMenu)|nil) - Called whenever the menu closes.

### Returns

- PallidRadialMenu - Configured menu (`Pallid.UI.Widgets.RadialMenu`).

### Methods
- `show(root, x, y) -> self` - Opens the ring with its centre at root-local `x`, `y`.
- `close() -> self` - Hides the menu and fires `onClose` once.
- `isOpen() -> boolean` - True while the menu is visible and not fading out.
- `getHovered() -> integer|nil, table|nil` - Hovered sector index and table; `nil, nil` for gaps and disabled sectors.
- `setSectors(sectors) -> self` - Replaces the sectors and rebuilds every derived value.
- `isInside(px, py) -> boolean` - True when the point lies on the visible disc.
- `listRect() -> x, y, w, h` - Root-local bounds including the shadow pad.

### Sector shape

- `label` (string|nil) - Sector caption.
- `icon` (string|nil) - Registered icon name or a texture path containing `/`.
- `color` (PallidColor|nil) - Per-sector fill; its hover state is derived from it.
- `disabled` (boolean|nil) - Draws a dimmed sector that cannot be selected.

### Example

```lua
local radial = Pallid.UI.Widgets.radialMenu({
    { label = "Wait" },
    { label = "Sleep" },
    { label = "Eat", icon = "media/assets/ui/pallid/icons/tick.png" },
    { label = "Locked", disabled = true },
}, {
    title = "Actions",
    onSelect = function(_, index, sector)
        -- use index or sector.label
    end,
})
radial:show(root, 400, 300) -- center of the ring, root-local
```

### Notes

- `show(root, x, y)` requires a root and at least one sector; an empty ring logs a message and does not open, because it would register an invisible popup that blocks the root.
- The center is clamped so the whole ring, shadow included, stays inside the root. `x` and `y` are the ring center, not its top-left corner.
- The menu attaches to `root.openPopup` and closes any other popup, menu or popover on that root first.
- Selection happens on release over an enabled sector. A release over a gap, the exact center or outside the disc does not select; a right click or Escape cancels.
- `innerRadius` is halved when it is greater than or equal to `outerRadius`.
- Colours and label anchors are computed in `setSectors`; change palette fields before calling `setSectors` again, or the cached per-sector colours stay stale.
- `setSectors(sectors)` replaces the sectors, resets the hover index and rebuilds all derived values. `isOpen()` and `getHovered()` are read-only; `getHovered()` returns `nil, nil` for gaps and disabled sectors.

## DragAndDrop

Process-wide drag session (`Pallid.UI.DragDrop`), a `Widgets.dragHandle` that starts the drag, and `Widgets.dropZone` targets that accept it. Only one drag can exist at a time.

**Side:** client

### Parameters

Module functions:

- `Pallid.UI.DragDrop.start(payload, source, root, px, py)` - Starts a session and returns `true` when it started. Cancels any previous session first.
- `Pallid.UI.DragDrop.move(px, py)` - Moves the ghost, calls `payload.onDragMove` and updates the zone under the pointer.
- `Pallid.UI.DragDrop.drop(px, py)` - Completes the session; returns `true` when it was dropped.
- `Pallid.UI.DragDrop.cancel()` - Cancels the session; returns `true` when one was active.
- `Pallid.UI.DragDrop.isActive(source)` - `true` while a session exists; with `source`, only for that source.
- `Pallid.UI.DragDrop.zoneAt(px, py)` - Returns the topmost zone under the point, or `nil`.
- `Pallid.UI.DragDrop.reset()` - Cancels the session and clears the zone registry (for host teardown).

Payload shape:

- `label` (string|nil) - Ghost label.
- `icon` (string|Texture|nil) - Ghost icon: texture path, registered name or Texture.
- `iconSize` (number|nil) - Icon box. Defaults to `14`.
- `color` (PallidColor|nil) - Accent for the ghost border and icon tint.
- `border` (PallidColor|nil) - Explicit ghost border; overrides `color`.
- `width`, `height` (number|nil) - Ghost size. Width is measured from the label up to `360`; height defaults to `28`.
- `offsetX`, `offsetY` (number|nil) - Cursor offset. Default to `12` and `8`.
- `kind` (string|nil) - Caller-defined kind, for `DropZone.accepts`.
- `dragData` (table|nil) - Caller-defined data for transfers.
- `onDragMove` (fun(px: number, py: number)|nil) - Called on every move with root-local coordinates.
- `onDrop` (fun(px: number, py: number): boolean|nil) - Return `true` to consume the drop and skip the `DropZone`.
- `onCancel` (fun()|nil) - Called when the session is cancelled.
- `onDragEnd` (fun(dropped: boolean)|nil) - Called exactly once when the session ends.

Factory: `Pallid.UI.Widgets.dragHandle(x, y, size, opts)`

- x, y (number) - Offset from the parent's origin.
- size (number) - Grip box side in pixels. Defaults to `18`.
- opts.payload (table|fun(handle: PallidDragHandle):table|nil) - Payload, or a factory called at drag start.
- opts.color (PallidColor|nil) - Grip tint.
- opts.hoverColor (PallidColor|nil) - Grip tint while hovered or dragging.
- opts.icon (string|false|nil) - Icon name or texture path; `false` hides the icon. Defaults to the grip icon.
- opts.iconSize (number|nil) - Explicit icon box, fitted inside the grip by default.
- opts.width, opts.height (number|nil) - Handle size; default to `size`.
- opts.plain (boolean|nil) - `true` draws no grip background, for a full-card drag surface.
- opts.hoverBorder (PallidColor|nil) - Outline drawn around a plain surface while hovered.
- opts.radius (number|nil) - Corner radius. Defaults to `3`.
- opts.threshold (number|nil) - Pixels the pointer must move before a drag starts. Defaults to `4`, minimum `1`.
- opts.acceptsFocus (boolean|nil) - Defaults to `true`; required for Escape to reach the handle.
- opts.onDragStart (fun(payload: table, source: PallidDragHandle)|nil) - Called after the session starts.
- opts.onDragEnd (fun(dropped: boolean, payload: table)|nil) - Called when the session ends.
- opts.onClick (fun(handle: PallidDragHandle)|nil) - Called on a press that never becomes a drag.

Factory: `Pallid.UI.Widgets.dropZone(x, y, w, h, opts)`

- x, y, w, h (number) - Zone bounds in the parent's coordinate space.
- opts.accepts (fun(payload: table, source: PallidWidget|nil, px: number, py: number): boolean|nil|false) - Predicate. Omitted accepts everything; `false` rejects everything.
- opts.onDrop (fun(payload: table, source: PallidWidget|nil, px: number, py: number)|nil) - Called when a payload is dropped on the zone.
- opts.onDragEnter (fun(payload: table, source: PallidWidget|nil, px: number, py: number)|nil) - Called when a payload enters the zone.
- opts.onDragMove (fun(payload: table, source: PallidWidget|nil, px: number, py: number)|nil) - Called while a payload hovers.
- opts.onDragLeave (fun(payload: table, source: PallidWidget|nil)|nil) - Called when a payload leaves the zone.
- opts.color (PallidColor|nil) - Valid highlight colour. Defaults to the accent token.
- opts.invalidColor (PallidColor|nil) - Invalid highlight colour. Defaults to the danger token.
- opts.background (PallidColor|nil) - Idle fill.
- opts.border (PallidColor|nil) - Idle border.
- opts.radius (number|nil) - Corner radius. Defaults to `4`.
- opts.alwaysOutline (boolean|nil) - Draws the idle outline even without a drag.
- opts.silent (boolean|nil) - Disables all zone painting.
- opts.priority (number|nil) - Higher priority wins when zones overlap.

### Returns

- PallidDragHandle - Handle widget (`Pallid.UI.Widgets.DragHandle`).
- PallidDropZone - Zone widget (`Pallid.UI.Widgets.DropZone`).

### Methods
- `Pallid.UI.DragDrop.start(payload, source, root, px, py) -> boolean` - Starts a session, cancelling any previous one first.
- `Pallid.UI.DragDrop.move(px, py) -> boolean` - Moves the ghost and updates the zone under the pointer.
- `Pallid.UI.DragDrop.drop(px, py) -> boolean` - Completes the session; `false` when no drag was active.
- `Pallid.UI.DragDrop.cancel() -> boolean` - Cancels the session; `false` when no drag was active.
- `Pallid.UI.DragDrop.isActive(source) -> boolean` - True while a session exists, with `source` only for that source.
- `Pallid.UI.DragDrop.zoneAt(px, py) -> PallidDropZone|nil` - Topmost zone under the point, or `nil`.
- `Pallid.UI.DragDrop.reset()` - Cancels the session and clears the zone registry.
- `dragHandle:setIcon(icon) -> self` - Replaces the grip icon; `false` hides it.
- `dragHandle:isDragging() -> boolean` - True while a drag started by this handle is active.
- `dropZone` - No methods beyond the base widget API in [ui-widget.md](ui-widget.md).

### Example

```lua
local sourceCard = Pallid.UI.Widgets.panel(8, 8, 240, 36, {})
page:add(sourceCard)

local zone = Pallid.UI.Widgets.dropZone(8, 60, 240, 80, {
    accepts = function(payload)
        return payload.kind == "item"
    end,
    onDrop = function(payload)
        -- use payload.dragData
    end,
})
page:add(zone)

local handle = Pallid.UI.Widgets.dragHandle(0, 0, 18, {
    payload = {
        label = "Sword",
        kind = "item",
        dragData = { id = "sword" },
    },
    onDragEnd = function(dropped)
        -- dropped is false on cancel
    end,
})
sourceCard:add(handle)
```

### Notes

- `start` returns `false` when the payload is not a table or the root is `nil`.
- A handle must be inside a tree attached to a root; the drag starts from the handle's root and all hook coordinates are root-local.
- A press only arms the handle; the session starts after the pointer moves `threshold` pixels, so a plain click fires `onClick` instead of flashing a ghost.
- Escape, a non-left press, losing focus, or releasing the left button outside the window cancels the drag.
- `onDrop` returning `true` marks the drop as handled and skips `DropZone` handling entirely.
- The ghost is painted by the root's overlay pass and is not part of the widget tree, so it never affects hit testing.
- Drop zones register while attached and unregister on detach; only visible zones on the active drag's root, with a non-zero size and not clipped away at the pointer, are considered.
- A zone that rejects a payload does not hide an accepting zone below it; `priority` breaks ties between overlapping zones.
- `DragDrop.reset()` should be called when a host or window is torn down, so detached zones do not stay registered.
