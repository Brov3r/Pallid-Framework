# Logging

`Pallid` provides one small logger that writes tagged lines through the game's `DebugLog`. Use it instead of `print` so every framework and mod line is identifiable in the console and log files.

Every line has the shape `[<tag>] [<LEVEL>] <text>`, for example `[Pallid:Core] [INFO] shop opened`. The tag is `Pallid:<module>` and the level is `INFO`, `WARN` or `ERROR`. Arguments are converted with `tostring`, joined with a single space, and written with `DebugLog.log(DebugType.Mod, line)`; the active DebugLog profile decides whether the line reaches the console and the log file. See also [net](net.md).

## Pallid.log

Writes an info line through the default logger.

**Side:** shared

### Parameters
- ... (any) - Values written on the line, converted with `tostring` and joined with a single space.

### Example
```lua
Pallid.log("shop opened for", player:getUsername())
-- [Pallid:Core] [INFO] shop opened for Brov3r
```

### Notes
- The default logger is created once with module name `Core`, so the tag is `Pallid:Core`, not `Pallid`.
- A `nil` argument inside the varargs is written as the text `nil`; a `nil` argument does not truncate the line.

## Pallid.warn

Writes a warning line through the default logger.

**Side:** shared

### Parameters
- ... (any) - Values written on the line, converted with `tostring` and joined with a single space.

### Example
```lua
Pallid.warn("missing config for", "Shop", "- using defaults")
-- [Pallid:Core] [WARN] missing config for Shop - using defaults
```

### Notes
- The `WARN` label is plain text inside the message. It does not change the DebugLog severity, so DebugLog severity filters do not apply to it.

## Pallid.error

Writes an error line through the default logger.

**Side:** shared

### Parameters
- ... (any) - Values written on the line, converted with `tostring` and joined with a single space.

### Example
```lua
Pallid.error("handler failed for action", action, ":", tostring(err))
-- [Pallid:Core] [ERROR] handler failed for action Shop_buy : attempt to index a nil value
```

### Notes
- This only writes a line. It does not throw, does not abort the caller and does not return a failure value; use `error()` when an invariant is broken and execution cannot continue.

## Pallid.getLogger

Creates a logger whose tag is `Pallid:<moduleName>`.

**Side:** shared

### Parameters
- moduleName (string) - Module name placed after `Pallid:` in every line.

### Returns
- PallidLogger - New logger instance. Every call returns a new table; loggers hold no shared state.

### Example
```lua
local logger = Pallid.getLogger("Shop")

logger:info("stock loaded", 12)
-- [Pallid:Shop] [INFO] stock loaded 12
```

### Notes
- The name is passed through `tostring`, so a non-string is accepted and a `nil` name produces the tag `Pallid:nil`. Always pass a real name.
- Store the logger in a `local` outside hot paths instead of creating one per call.

## PallidLogger:info

Writes an `INFO` line with this logger's tag.

**Side:** shared

### Parameters
- ... (any) - Values written on the line, converted with `tostring` and joined with a single space.

### Example
```lua
local logger = Pallid.getLogger("Net")

logger:info("connected as", "client")
-- [Pallid:Net] [INFO] connected as client
```

### Notes
- The method returns nothing, so it cannot be used in a condition or chained.

## PallidLogger:warn

Writes a `WARN` line with this logger's tag.

**Side:** shared

### Parameters
- ... (any) - Values written on the line, converted with `tostring` and joined with a single space.

### Example
```lua
local logger = Pallid.getLogger("Net")

logger:warn("dropped message with protocol version", 2)
-- [Pallid:Net] [WARN] dropped message with protocol version 2
```

## PallidLogger:error

Writes an `ERROR` line with this logger's tag.

**Side:** shared

### Parameters
- ... (any) - Values written on the line, converted with `tostring` and joined with a single space.

### Example
```lua
local logger = Pallid.getLogger("Net")

logger:error("sendClientCommand failed for", "Shop_buy")
-- [Pallid:Net] [ERROR] sendClientCommand failed for Shop_buy
```

### Notes
- Like `Pallid.error`, this only writes a line and never throws.
