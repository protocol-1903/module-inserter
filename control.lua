local function valid(inserter)
  metadata = storage[inserter.unit_number]
  -- if not valid, then remove entities (will most always be inserters being invalid)
  if not metadata then return true end
  if not metadata.inserter.valid or (metadata.pickup_target and not metadata.pickup_target.valid) or (metadata.drop_target and not metadata.drop_target.valid) then
    if metadata.inserter.valid then metadata.inserter.destroy() end
    if metadata.pickup_target.valid then metadata.pickup_target.destroy() end
    if metadata.drop_target.valid then metadata.drop_target.destroy() end
    storage[index] = nil
    return false
  end
  return true
end

script.on_configuration_changed(function (event)
  for _, metadata in pairs(storage) do
    valid(metadata.inserter)
  end
end)

local function update_targets(inserter)
  if inserter and storage[inserter.unit_number] then
    for index, entity in pairs(storage[inserter.unit_number]) do
      if index ~= "inserter" then
        -- move entity to new target position
        entity.teleport(inserter[index == "drop_target" and "drop_position" or "pickup_position"])
        target = entity.surface.find_entities_filtered{
          position = entity.position,
          type = {
            "furnace",
            "assembling-machine",
            "lab",
            "mining-drill"
          }
        }[1]

        -- set new target, will automatically fail if target does not exist
        entity.proxy_target_entity = target
        entity.proxy_target_inventory = target and target_inventory_types[target.type] or 0
        inserter[index] = entity
      end
    end
  end
end

local function update_gui(inserter, player)
  if not inserter or inserter.type ~= "inserter" then return end
  if not valid(inserter) then return end
  if player.gui.relative["module-inserter-gui"] then
    player.gui.relative["module-inserter-gui"].destroy()
  end

  local window = player.gui.relative.add{
    type = "frame",
    name = "module-inserter-gui",
    caption = { "mi-window.frame" },
    direction = "vertical",
    anchor = {
      gui = defines.relative_gui_type.inserter_gui,
      position = defines.relative_gui_position.right
    }
  }.add{
    type = "frame",
    style = "inside_shallow_frame_with_padding_and_vertical_spacing",
    direction = "vertical"
  }
  window.add{
    type = "checkbox",
    name = "drop_target",
    style = "caption_checkbox",
    state = inserter.tags and inserter.tags["module-inserter"].drop_target or storage[inserter.unit_number] and storage[inserter.unit_number].drop_target and true or false,
    caption = { "mi-window.insert" }
  }
  window.add{
    type = "checkbox",
    name = "pickup_target",
    style = "caption_checkbox",
    state = inserter.tags and inserter.tags["module-inserter"].pickup_target or storage[inserter.unit_number] and storage[inserter.unit_number].pickup_target and true or false,
    caption = { "mi-window.remove" }
  }
end

script.on_event(defines.events.on_gui_opened, function (event)
  update_gui(event.entity, game.players[event.player_index])
end)

target_inventory_types = {
  ["furnace"] = defines.inventory.crafter_modules,
  ["assembling-machine"] = defines.inventory.crafter_modules,
  ["lab"] = defines.inventory.lab_modules,
  ["mining-drill"] = defines.inventory.mining_drill_modules,
  ["proxy-container"] = ":D"
}

script.on_event(defines.events.on_gui_click, function (event)
  if event.element.get_mod() ~= "module-inserter" or event.element.type ~= "checkbox" then return end

  local player = game.players[event.player_index]
  local inserter = player.opened

  if inserter.type == "entity-ghost" then
    -- tags = inserter.tags or {}
    -- tags["module-inserter"] = event.element.state
    -- inserter.tags = tags
  else
    local target = inserter[event.element.name]
    if event.element.state then
      -- create proxy container
      local proxy = inserter.surface.create_entity{
        name = "module-inserter-target",
        force = inserter.force,
        position = event.element.name == "drop_target" and inserter.drop_position or inserter.pickup_position
      }
      -- set target, will automatically fail if it does not exist
      proxy.proxy_target_entity = target
      proxy.proxy_target_inventory = target and target_inventory_types[target.type] or 0
      -- save to storage for later reference
      local metadata = storage[inserter.unit_number] or { inserter = inserter }
      metadata[event.element.name] = proxy
      inserter[event.element.name] = proxy
      storage[inserter.unit_number] = metadata
    else
      -- delete proxy container and remove it's reference
      target.destroy()
      storage[inserter.unit_number][event.element.name] = nil
      -- remove from storage if neither exists
      if not storage[inserter.unit_number].drop_target and not storage[inserter.unit_number].pickup_target then
        storage[inserter.unit_number] = nil
      end
    end
  end
end)

script.on_event(defines.events.on_gui_closed, function (event)
  if game.players[event.player_index].gui.relative["module-inserter-gui"] then
    game.players[event.player_index].gui.relative["module-inserter-gui"].destroy()
  end
end)

--- @param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_space_platform_built_entity|EventData.script_raised_built|EventData.script_raised_revive|EventData.on_cancelled_deconstruction
local function on_created(event)
  if event.entity.type == "inserter" and event.tags and event.tags["module-inserter"] then
    -- create relevant entities
  elseif event.entity.type ~= "inserter" then
    -- connect proxies to newly created entity
    local target = event.entity
    for _, proxy in pairs(target.surface.find_entities_filtered{
      area = target.bounding_box,
      name = "module-inserter-target"
    }) do
      proxy.proxy_target_entity = target
      proxy.proxy_target_inventory = target_inventory_types[target.type]
    end
  end
end

--- @param event EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.on_space_platform_mined_entity|EventData.script_raised_destroy|EventData.on_entity_died
local function on_destroyed(event)
  for _, entity in pairs(storage[event.entity.unit_number] or {}) do
    if entity.type == "proxy-container" then entity.destroy() end
  end
  storage[event.entity.unit_number] = nil
end

event_filter = {
  {filter = "type", type = "inserter"},
  {filter = "type", type = "furnace"},
  {filter = "type", type = "assembling-machine"},
  {filter = "type", type = "lab"},
  {filter = "type", type = "mining-drill"}
}

script.on_event(defines.events.on_built_entity, on_created, event_filter)
script.on_event(defines.events.on_robot_built_entity, on_created, event_filter)
script.on_event(defines.events.on_space_platform_built_entity, on_created, event_filter)
script.on_event(defines.events.script_raised_built, on_created, event_filter)
script.on_event(defines.events.script_raised_revive, on_created, event_filter)

-- only needs to register for inserter removal
script.on_event(defines.events.on_player_mined_entity, on_destroyed, {{filter = "type", type = "inserter"}})
script.on_event(defines.events.on_robot_mined_entity, on_destroyed, {{filter = "type", type = "inserter"}})
script.on_event(defines.events.on_space_platform_mined_entity, on_destroyed, {{filter = "type", type = "inserter"}})
script.on_event(defines.events.script_raised_destroy, on_destroyed, {{filter = "type", type = "inserter"}})
script.on_event(defines.events.on_entity_died, on_destroyed, {{filter = "type", type = "inserter"}})

script.on_event(defines.events.on_player_rotated_entity, function (event)
  update_targets(event.entity)
end)

script.on_event(defines.events.on_entity_settings_pasted, function (event)

end)

script.on_event(defines.events.on_player_setup_blueprint, function (event)

end)

script.on_event(defines.events.on_player_configured_blueprint, function (event)

end)

if script.active_mods["quick-adjustable-inserters"] then
  ---@param event EventData.on_qai_inserter_vectors_changed
  script.on_event(defines.events.on_qai_inserter_vectors_changed, function(event)
    update_targets(event.inserter)
  end)

  ---@param event EventData.on_qai_inserter_adjustment_finished
  script.on_event(defines.events.on_qai_inserter_adjustment_finished, function(event)
    update_targets(event.inserter)
  end)
end