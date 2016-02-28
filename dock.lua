local setmetatable = setmetatable
local math = math
local base        = require( "radical.base"               )
local color       = require( "gears.color"                )
local wibox       = require( "wibox"                      )
local beautiful   = require( "beautiful"                  )
local vertical    = require( "radical.layout.vertical"    )
local horizontal  = require( "radical.layout.horizontal"  )
local item_layout = require( "radical.item.layout.icon"   )
local item_style  = require( "radical.item.style.rounded" )
local hot_corner  = require( "radical.hot_corner"         )
local shape       = require( "gears.shape"                )
local common      = require( "radical.common"             )
local smart_wibox = require( "radical.smart_wibox"        )
local placement   = require( "radical.placement"          )

local default_radius = 10
local rad = beautiful.dock_corner_radius or default_radius
local default_shape =  function(cr, width, height) shape.partially_rounded_rect(cr, width, height, false, true, true, false, rad) end

local capi,module = { mouse = mouse , screen = screen, keygrabber = keygrabber },{}
local max_size = {height={},width={}}

-- Compute the optimal maxmimum size
local function get_max_size(data,screen)
    local dir = "left"
    local w_or_h = ((dir == "left" or dir == "right") and "height" or "width")
    local x_or_y = w_or_h == "height" and "y" or "x"
    local res = max_size[w_or_h][screen]
    if not res then
        local full,wa = capi.screen[screen].geometry[w_or_h],capi.screen[screen].workarea
        local top,bottom = wa[x_or_y],full-(wa.y+wa[w_or_h])
        local biggest = top > bottom and top or bottom
        --res = full - biggest*2 - 52 -- 26px margins
        local margin = beautiful.dock_margin or 52
        res = wa[w_or_h] - margin
        max_size[w_or_h][screen] = res
    end
    return res
end

--TODO it still works, but rewrite this code anyway
-- The dock always have to be shorter than the screen
local function adapt_size(data,w,h,screen)
    local max = get_max_size(data,screen)

    -- Get the current size, then compare and ajust
    local fit_w,fit_h = data._internal.layout:get_preferred_size({dpi=96,force_values=true},beautiful.default_height)

    -- Get the number of items minus the number of widgets
    -- This can be used to approximate the number of pixel to remove
    local visible_item = data.visible_row_count - #data._internal.widgets + 1

    local orientation = "vertical"

    if orientation == "vertical" and h > max then
        local wdg_height = data.widget_fit_height_sum
        --TODO this assume the widget size wont change
    --     data.item_height = math.ceil((data.item_height*max)/h) --OLD
        data.item_height = math.ceil((max-wdg_height)/visible_item)
        w = data.item_height
        h = max
        data.item_width  = w
        data.menu_width  = w
        w = w + data.margins.left+data.margins.right
        data.default_width = w
        data._internal.private_data.width = w
    elseif orientation == "horizontal" and w > max then
        --TODO merge this with above
        local wdg_width = data.widget_fit_width_sum
        data.item_width = math.ceil((data.item_height*max)/w)
        data._internal.private_data = data.item_width
        w = max
        h = data.item_width
        data.item_height  = h
        data.menu_height  = h
        h = h + data.margins.bottom+data.margins.top
    --     data.default_width = h
    end
    if data.icon_size and data.icon_size > w then
        data.icon_size = w
    end

    data._internal.margin:emit_signal("widget::layout_changed")
    data._internal.margin:emit_signal("widget::redraw_needed")

    return w == 0 and 1 or w, h == 0 and 1 or h
end

-- Create the main wibox (lazy-loading)
local function get_wibox(data, screen)
    if data._internal.w then return data._internal.w end

    data._internal.margin = wibox.layout.margin(data._internal.layout)

    local w = smart_wibox(data._internal.margin, {
        screen             = screen                                         ,
        ontop              = true                                           ,
        shape              = beautiful.dock_shape or default_shape          ,
        shape_border_width = 1                                              ,
        shape_border_color = color(data.border_color or data.fg            ),
        bg                 = color(beautiful.bg_dock or beautiful.bg_normal),
    })

    data._internal.w = w

    data:emit_signal("visible::changed",true)

    w:connect_signal("property::height",function()
        adapt_size(data, w.width, w.height, 1)
    end)

    placement.pin(w, placement.corner, "left", screen or 1)

    return w
end

local function setup_drawable(data)
    local internal = data._internal

    -- Create the layout
    internal.layout = data.layout(data)

    -- Getters
    data.get_visible = function() return true end
    data.get_margins = common.get_margins

    function data:set_visible(value)
        if internal.w then
        internal.w.visible = value or false
        end
    end

    common.setup_item_move_events(data)
end

local function new(args)
    local args = args or {}
    local orientation = (not args.position or args.position == "left" or args.position == "right") and "vertical" or "horizontal"
    local length_inv  = orientation == "vertical" and "width" or "height"

    -- The the Radical arguments
    args.internal = args.internal or {}
    args.internal.orientation = orientation
    args.internal.setup_drawable = args.internal.setup_drawable or setup_drawable
    args.internal.setup_item     = args.internal.setup_item     or common.setup_item
    args.item_style              = args.item_style              or item_style
    args.bg                   = color("#00000000") --Use the dock bg instead
    args.item_height          = 40
    args.item_width           = 40
    args.sub_menu_on          = args.sub_menu_on or base.event.BUTTON1
    args.internal             = args.internal or {}
    args.internal.layout_func = orientation == "vertical" and vertical or horizontal
    args.layout               = args.layout or args.internal.layout_func
    args.item_style           = args.item_style or item.style
      args.item_layout          = args.item_layout or item_layout
    args[length_inv]          = args[length_inv] or 40

    -- Create the dock
    local ret = base(args)
    ret.position = args.position or "left"
    ret.screen = args.screen or 1

    -- Add a 1px placeholder to trigger it
    if not beautiful.dock_always_show then
        hot_corner.register_wibox(ret.position, function()
            return get_wibox(ret, 1)
        end, ret.screen, 1)
    else
        timer.delayed_call(function()
            local w = get_wibox(ret, 1)
            w.visible = true
        end)
    end

    return ret
end

return setmetatable(module, { __call = function(_, ...) return new(...) end })
-- kate: space-indent on; indent-width 4; replace-tabs on;
