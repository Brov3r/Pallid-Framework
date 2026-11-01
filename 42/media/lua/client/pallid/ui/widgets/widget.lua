-- The base widget is split by responsibility so no single file owns the whole
-- contract. Keep this file as the only entry point: every widget requires
-- "pallid/ui/widgets/widget" and gets the complete class.
--
-- Load order matters: widget/core.lua defines Widgets.Widget, the other parts
-- attach methods to it and require the core themselves.
require "pallid/ui/widgets/widget/core"
require "pallid/ui/widgets/widget/input"
require "pallid/ui/widgets/widget/overlay"
