# Pallid Framework documentation

A Project Zomboid Build 42 library for networking, UI widgets, drawing, animation and gameplay helpers, exposed through the `Pallid` global.

| Topic | File |
| --- | --- |
| Logging helpers and the `PallidLogger` class | [logger.md](logger.md) |
| Client/server message layer `Pallid.Net` | [net.md](net.md) |
| Custom traits | [gameplay-traits.md](gameplay-traits.md) |
| Custom professions | [gameplay-professions.md](gameplay-professions.md) |
| Custom moodles, renderer and multiplayer state | [gameplay-moodles.md](gameplay-moodles.md) |
| Full-screen UI host element | [ui-host.md](ui-host.md) |
| Base widget class and retained tree | [ui-widget.md](ui-widget.md) |
| Colors and the shared palette | [ui-color.md](ui-color.md) |
| Points, shapes and hit tests | [ui-geometry.md](ui-geometry.md) |
| Clip stack | [ui-clipping.md](ui-clipping.md) |
| Rectangles, lines, polygons and progress | [ui-draw.md](ui-draw.md) |
| Fonts, text styles and text measurement | [ui-text.md](ui-text.md) |
| Textures, icons, emoji and the asset table | [ui-textures.md](ui-textures.md) |
| Easing, tracks, presets and animated drawing | [ui-animation.md](ui-animation.md) |
| Windows, panels and layout containers | [widgets-layout.md](widgets-layout.md) |
| Scroll panels, split panels, scroll bars and spacers | [widgets-scroll.md](widgets-scroll.md) |
| Labels, buttons, images, badges and feedback | [widgets-basic.md](widgets-basic.md) |
| Text, numeric and masked input controls | [widgets-input.md](widgets-input.md) |
| Dropdowns, combo boxes and selection controls | [widgets-select.md](widgets-select.md) |
| Tables, trees, lists, property grids and query builders | [widgets-data.md](widgets-data.md) |
| Pagination, tabs, steppers and breadcrumbs | [widgets-navigation.md](widgets-navigation.md) |
| Dialogs, tooltips, menus and drag-and-drop | [widgets-overlay.md](widgets-overlay.md) |
| Charts, color pickers, 3D models and date/time pickers | [widgets-charts.md](widgets-charts.md) |

## Widgets

Every factory below is reached through `Pallid.UI.Widgets`. Each link goes to the widget's own section.

### Layout and containers

- [Window](widgets-layout.md#widgetswindow)
- [Panel](widgets-layout.md#widgetspanel)
- [GroupBox](widgets-layout.md#widgetsgroupbox)
- [HBox](widgets-layout.md#widgetshbox)
- [VBox](widgets-layout.md#widgetsvbox)
- [Grid](widgets-layout.md#widgetsgrid)
- [Stack](widgets-layout.md#widgetsstack)
- [Flow](widgets-layout.md#widgetsflow)

### Scroll and spacing

- [SplitPanel](widgets-scroll.md#splitpanel)
- [ScrollPanel](widgets-scroll.md#scrollpanel)
- [ScrollBar](widgets-scroll.md#scrollbar)
- [Separator](widgets-scroll.md#separator)
- [Spacer](widgets-scroll.md#spacer)
- [Anchor](widgets-scroll.md#anchor)

### Basic controls

- [Label](widgets-basic.md#label)
- [Button](widgets-basic.md#button)
- [SplitButton](widgets-basic.md#splitbutton)
- [Badge](widgets-basic.md#badge)
- [Hyperlink](widgets-basic.md#hyperlink)
- [Image](widgets-basic.md#image)
- [ImageGallery](widgets-basic.md#imagegallery)
- [Avatar](widgets-basic.md#avatar)
- [Keycap](widgets-basic.md#keycap)
- [ProgressBar](widgets-basic.md#progressbar)
- [Spinner](widgets-basic.md#spinner)
- [Skeleton](widgets-basic.md#skeleton)
- [EmptyState](widgets-basic.md#emptystate)
- [Alert](widgets-basic.md#alert)
- [RichText](widgets-basic.md#richtext)

### Input

- [InputText](widgets-input.md#inputtext)
- [InputArea](widgets-input.md#inputarea)
- [InputPassword](widgets-input.md#inputpassword)
- [InputRich](widgets-input.md#inputrich)
- [Checkbox](widgets-input.md#checkbox)
- [Slider](widgets-input.md#slider)
- [RangeSlider](widgets-input.md#rangeslider)
- [Knob](widgets-input.md#knob)
- [NumberStepper](widgets-input.md#numberstepper)
- [UnitInput](widgets-input.md#unitinput)
- [DurationInput](widgets-input.md#durationinput)
- [Keybind](widgets-input.md#keybind)
- [TagInput](widgets-input.md#taginput)
- [SearchField](widgets-input.md#searchfield)
- [FormField](widgets-input.md#formfield)

### Selection

- [Dropdown](widgets-select.md#dropdown)
- [ComboBox](widgets-select.md#combobox)
- [MultiSelect](widgets-select.md#multiselect)
- [MultiSelectComboBox](widgets-select.md#multiselectcombobox)
- [RadioGroup](widgets-select.md#radiogroup)
- [ToggleGroup](widgets-select.md#togglegroup)
- [SegmentedControl](widgets-select.md#segmentedcontrol)
- [OptionList](widgets-select.md#optionlist)
- [ListBox](widgets-select.md#listbox)
- [PickerField](widgets-select.md#pickerfield)

### Data

- [Table](widgets-data.md#table-palliduiwidgetstable)
- [TreeView](widgets-data.md#treeview-palliduiwidgetstreeview)
- [VirtualList](widgets-data.md#virtuallist-palliduiwidgetsvirtuallist)
- [ReorderableList](widgets-data.md#reorderablelist-palliduiwidgetsreorderablelist)
- [PropertyGrid](widgets-data.md#propertygrid-palliduiwidgetspropertygrid)
- [QueryBuilder](widgets-data.md#querybuilder-palliduiwidgetsquerybuilder)

### Navigation

- [Pagination](widgets-navigation.md#pagination)
- [FilterBar](widgets-navigation.md#filterbar)
- [Timeline](widgets-navigation.md#timeline)
- [Stepper](widgets-navigation.md#stepper)
- [TabPanel](widgets-navigation.md#tabpanel)
- [Accordion](widgets-navigation.md#accordion)
- [Breadcrumbs](widgets-navigation.md#breadcrumbs)

### Overlays and drag-and-drop

- [ModalDialog](widgets-overlay.md#modaldialog)
- [ConfirmDialog](widgets-overlay.md#confirmdialog)
- [PromptDialog](widgets-overlay.md#promptdialog)
- [Tooltip](widgets-overlay.md#tooltip)
- [Toast](widgets-overlay.md#toast)
- [Popover](widgets-overlay.md#popover)
- [Menu](widgets-overlay.md#menu)
- [MenuBar](widgets-overlay.md#menubar)
- [ContextMenu](widgets-overlay.md#contextmenu)
- [RadialMenu](widgets-overlay.md#radialmenu)
- [DragAndDrop](widgets-overlay.md#draganddrop) (`dragHandle`, `dropZone`)

### Charts and pickers

- [Chart](widgets-charts.md#chart)
- [DonutChart](widgets-charts.md#donutchart)
- [ColorPicker](widgets-charts.md#colorpicker)
- [Model3D](widgets-charts.md#model3d)
- [DatePicker](widgets-charts.md#datepicker)
- [TimePicker](widgets-charts.md#timepicker)
