-- The tooltip is split by responsibility so no single file owns the whole
-- contract. Keep this file as the only entry point: every widget requires
-- "pallid/ui/widgets/tooltip" and gets the complete class, the cached layout,
-- the shared native host and the draw method.
--
-- Load order matters: tooltip/core.lua defines Widgets.Tooltip, the other parts
-- attach methods to it or use it at draw time.
require "pallid/ui/widgets/tooltip/core"
require "pallid/ui/widgets/tooltip/layout"
require "pallid/ui/widgets/tooltip/host"
require "pallid/ui/widgets/tooltip/draw"
