-- from features/gui/camera
-- edited to support "opposite surface"
local Event = require 'utils.event'
local mod_gui = require 'mod-gui'
local Gui = require 'utils.gui'
local Global = require 'utils.global'

local main_button_name = Gui.uid_name()

local camera_users = {}
Global.register({ camera_users = camera_users }, function(tbl)
  camera_users = tbl.camera_users
end)

local camera_prototype = 'camera'
local zoomlevels = { 1.00, 0.75, 0.50, 0.40, 0.30, 0.25, 0.20, 0.15, 0.10, 0.05 }
local zoomlevellabels = { '100%', '75%', '50%', '40%', '30%', '25%', '20%', '15%', '10%', '5%' }
local sizelevels = { 0, 100, 200, 250, 300, 350, 400, 450, 500 }
local sizelevellabels = { 'hide', '100x100', '200x200', '250x250', '300x300', '350x350', '400x400', '450x450', '500x500' }

---@param surface SurfaceIdentification union LuaSurface|string
local function get_opposite_surface(surface)
  local src = game.get_surface(type(surface) == 'table' and surface.name or surface)
  local mines = game.get_surface('mines')
  local islands = game.get_surface('islands')

  if not islands or not mines or not src then
    return
  end

  if src.name == mines.name then
    return islands
  end
  if src.name == islands.name then
    return mines
  end
  return
end

--- Takes args and a LuaPlayer and creates a camera GUI element
local function create_camera(args, player)
  local player_index = player.index
  local mainframeflow = mod_gui.get_frame_flow(player)
  local mainframeid = 'mainframe_' .. player_index
  local mainframe = mainframeflow[mainframeid]

  local target = game.get_player(args.target)
  if not target then
    player.print('Not a valid target')
    return
  end

  if not mainframe then
    mainframe = mainframeflow.add { type = 'frame', name = mainframeid, direction = 'vertical', style = 'captionless_frame' }
    mainframe.visible = true
    player.set_shortcut_toggled(camera_prototype, true)
  end

  local headerframe = mainframe.headerframe
  if not headerframe then
    mainframe.add { type = 'frame', name = 'headerframe', direction = 'horizontal', style = 'captionless_frame' }
  end

  local cameraframe = mainframe.cameraframe
  if not cameraframe then
    mainframe.add { type = 'frame', name = 'cameraframe', style = 'captionless_frame' }
  end

  mainframe.add { type = 'label', caption = 'Following: ' .. target.name .. '\'s steps on other surface' }
  Gui.make_close_button(mainframe, main_button_name)
  local target_index = target.index
  camera_users[player_index] = target_index
end

--- Takes table with a LuaPlayer under key player and destroys the camera of the associated player
local function destroy_camera(data)
  local player = data.player
  if not player then
    return
  end

  local player_index = player.index
  local mainframeflow = mod_gui.get_frame_flow(player)
  local mainframeid = 'mainframe_' .. player_index
  local mainframe = mainframeflow[mainframeid]

  if mainframe then
    mainframe.destroy()
    player.set_shortcut_toggled(camera_prototype, false)
    return true
  end
end

--- Destroys existing camera and, if applicable, creates a new one for the new target.
local function camera_command(args, player)
  destroy_camera({ player = player })
  -- Once the old camera is destroyed, check to see if we need to make a new one
  if global.config.camera_disabled then
    player.print('The watch/camera function has been disabled for performance reasons.')
    return
  end
  if args and args.target and player then
    create_camera(args, player)
  end
end

local function update_camera_render(target, targetframe, zoom, size, visible)
  local position = { x = target.position.x, y = target.position.y - 0.5 }
  local surface_index = target.surface.index
  local preview_size = size
  local camera = targetframe.camera

  if not camera then
    camera = targetframe.add { type = 'camera', name = 'camera', position = position, surface_index = surface_index, zoom = zoom }
  end

  camera.position = position
  camera.surface_index = get_opposite_surface(surface_index).index
  camera.zoom = zoom
  camera.visible = visible
  camera.style.minimal_width = preview_size
  camera.style.minimal_height = preview_size
  camera.style.maximal_width = preview_size
  camera.style.maximal_height = preview_size
end

local function update_camera_zoom(targetframe)
  local zoomselection = targetframe.zoomselection
  local zoomlabels = {}

  for i = 1, #zoomlevellabels do
    zoomlabels[i] = { '', '' .. zoomlevellabels[i] }
  end
  if zoomselection then
    zoomselection.items = zoomlabels
  else
    zoomselection = targetframe.add { type = 'drop-down', name = 'zoomselection', items = zoomlabels, selected_index = 3 }
  end

  local zoom = zoomlevels[zoomselection.selected_index]
  return zoom
end

local function update_camera_size(targetframe)
  local sizeselection = targetframe.sizeselection
  local sizelabels = {}

  for i = 1, #sizelevellabels do
    sizelabels[i] = { '', '' .. sizelevellabels[i] }
  end
  if sizeselection then
    sizeselection.items = sizelabels
  else
    sizeselection = targetframe.add { type = 'drop-down', name = 'sizeselection', items = sizelabels, selected_index = 4 }
  end

  local size = sizelevels[sizeselection.selected_index]
  local visible = (size ~= 0)
  return size, visible
end

local function on_tick()
  if global.config.camera_disabled then
    return
  end
  for table_key, camera_table in pairs(camera_users) do
    local player = game.get_player(table_key)
    local target = game.get_player(camera_table)
    if not target.connected then
      destroy_camera({ player = player })
      player.print('Target is offline, camera closed')
      camera_users[player.index] = nil
      return
    end
    local mainframeflow = mod_gui.get_frame_flow(player)
    local mainframeid = 'mainframe_' .. table_key
    local mainframe = mainframeflow[mainframeid]
    if mainframe then
      local headerframe = mainframe.headerframe
      local cameraframe = mainframe.cameraframe
      local zoom = update_camera_zoom(headerframe)
      local size, visible = update_camera_size(headerframe)
      update_camera_render(target, cameraframe, zoom, size, visible)
      player.set_shortcut_toggled(camera_prototype, visible)
    end
  end
end

local function on_lua_shortcut(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then
    return
  end

  local shortcut = event.prototype_name or event.input_name
  if shortcut ~= camera_prototype then
    return
  end

  local toggled = player.is_shortcut_toggled(camera_prototype)
  player.set_shortcut_toggled(camera_prototype, not toggled)

  if toggled then
    destroy_camera({ player = player })
  else
    camera_command({ target = player.name }, player)
  end
end

Event.on_nth_tick(61, on_tick)
Gui.on_click(main_button_name, destroy_camera)

Event.add(defines.events.on_lua_shortcut, on_lua_shortcut)
-- luacheck: ignore script
script.on_event(camera_prototype, on_lua_shortcut)