pico-8 cartridge // http://www.pico-8.com
version 30
__lua__

-- global variables (or, variables needed outside of or between screens)
-- current screen being shown
screen = nil

-- whether the screen transition animation is being shown
switching = nil

-- mouse state the last update, used in a few places outside/inside current screen
last_mouse = {v=0, x=0, y=0}

-- causes the mouse to be set to unclicked while held down between screen transitions
-- so holding the mouse doesn't take you through multiple screens
waiting_for_let_go = false
-- end: global variables

-- constants
-- sentinel value to indicate there's no hex here in the hexes table
-- tables must be contiguous (and start from 1) for pairs/ipairs to work >:(
no_hex = {}
-- end constants

-- pico-8 hooks
function _init()
 poke(0x5f2d, 3)
 cartdata("cat_beecells_1")
 load_save()

 switch_screen(menu)
end

function _update()
 local curr_x, curr_y, mouse = stat(32), stat(33), stat(34)

 if mouse == 0 then
  waiting_for_let_go = false
 end

 if waiting_for_let_go then
  mouse = 0
 end

 if switching then
  switch.update()
 else -- in an else to pause the current screen for more retro loady feel, not required
  screen.update(curr_x, curr_y, mouse, stat(36))
 end

 last_mouse = {v=mouse, x=curr_x, y=curr_y}
end

function _draw()
 rectfill(0, 0, 128, 128, 10)

 screen.draw()

 if switching then -- needs to be after new screen draw because this draws over
  switch.draw()
 end

 -- cursor
 -- last_mouse here is current, since draw happens after update
 spr(65, last_mouse.x, last_mouse.y, 2, 2)
end
-- end: pico-8 hooks

-- creates a screen
function screenm(init, update, draw)
 return {init=init, update=update, draw=draw, data={}}
end

--- switch: a pseudo-screen that shows the screen transition animation
function _init_switch()
 switch.data.old_screen_height = 128
 switch.data.frame_counter = 0

 switch.data.bees = line_of_bees()

 -- save what's currently being shown (the old screen) to apply the transition effect
 local old_screen = {} -- fill local on purpose: 128*64 accesses to a.b.c causes visible stutter

 for i=0, 127 do
  old_screen[i] = {}
  for k=0, 63 do
   old_screen[i][k] = @(0x6000 + 64 * i + k)
  end
 end

 switch.data.old_screen = old_screen
end

function _update_switch()
 switch.data.old_screen_height -= 3.5
 switch.data.frame_counter += 1

 if switch.data.frame_counter % 10  == 0 then
  switch.data.bees = line_of_bees()
 end

 if switch.data.old_screen_height <= -8 then
  switching = false
  switch.data.old_screen = nil -- intentionally release 8 kib of old screen data when no longer needed
 end

end

function _draw_switch()
 local old_screen, old_screen_height = switch.data.old_screen, switch.data.old_screen_height


 -- fill old screen from top down, up to the current height
 for i=0, min(old_screen_height, 127) do
  for k=0, 63 do
   poke(0x6000 + 64 * i + k, old_screen[i][k])
  end
 end

 -- then draw bees to hide screen tear
 for _, bee in pairs(switch.data.bees) do
  spr(64, bee.x, old_screen_height + bee.y)
 end
end

switch = screenm(_init_switch, _update_switch, _draw_switch)
-- end: switch

--- menu: the title menu, showing the game name
function _init_menu()
 screen.data.play_blink_t = 0
 update_hex_side_length(8)
 x_pan = 0
 y_pan = 0

 screen.data.menu_bees = {}

 for i=0, flr(rnd(3)) + 3 do
  local jitter_chance = rnd(1)
  if jitter_chance < 0.3 then
   jitter_chance = 0.3
  end
  screen.data.menu_bees[#screen.data.menu_bees + 1] = {x=16 + rnd(128 - 32), y=16 + rnd(128 - 32), jitter_chance=jitter_chance}
 end
end

function _update_menu(curr_x, curr_y, curr_mouse, scroll)
 screen.data.play_blink_t += 1
 if screen.data.play_blink_t == 60 then
  screen.data.play_blink_t = 0
 end

 if screen.data.play_blink_t % 10 == 0 then
  for _, bee in pairs(screen.data.menu_bees) do
   if rnd(1) < bee.jitter_chance then
    bee.x += rnd(5) - 2.5
    bee.y += rnd(5) - 2.5
   end
  end
 end

 if curr_mouse == 1 then
  switch_screen(level_select)
 end
end

function _draw_menu()
 for col=0, 10 do
  for row=0, 9 do
   draw_hex(hexm(col, row))
  end
 end

 spr(1, 4, 16, 15, 4) -- logo
 spr(67, 4 + 15 * 8 / 2 - 6 * 8 / 2, 48, 6, 2) -- author

 for _, bee in pairs(screen.data.menu_bees) do
  spr(64, bee.x, bee.y)
 end

 if screen.data.play_blink_t < 30 then
  text("click to play", 41, 100, 51, 13)
 end
end

menu = screenm(_init_menu, _update_menu, _draw_menu)
-- end: menu

--- level select: the screen which lets you choose a puzzle to solve
function _init_level_select()
 update_hex_side_length(10)
 x_pan = -hex_width / 2 -- + (128-hex_col_mult * 7.5) / 2
 y_pan = -hex_height * 1.25  --hex_height / 2 + (128- hex_height * 7) / 2

 local hexes={}
 for col=1, 8 do
  hexes[col]={}
  for row=1, 8 do
   if col % 2 == 1 or row % 2 == 1 then
    hexes[col][row] = no_hex
   else
    hexes[col][row] = hexm(col, row, false, true)
    hexes[col][row].n = ((col - 2) / 2) + ((row - 2) / 2) * 4 + 1
   end
  end
 end

 screen.data.hexes = hexes

 screen.data.color_func = function (hex)
  if puzzles[hex.n] != nil and puzzles[hex.n].solved then
   return 3
  else
   return nil
  end
 end
end


function _update_level_select(curr_x, curr_y, curr_mouse, scroll)
 if curr_mouse == 2 then
  switch_screen(menu)
  return
 end

 local hex = hovered_hex(curr_x, curr_y, curr_mouse)
 if hex != nil and curr_mouse == 1 then
  switch_screen(puzzle, {level=hex.n})
 end
end


function _draw_level_select()
 draw_hexes(true)
end

level_select = screenm(_init_level_select, _update_level_select, _draw_level_select)
-- end: level select

-- puzzle: a puzzle to be solved
function _init_puzzle()
 update_hex_side_length(puzzles[screen.data.level].size)
 x_pan = puzzles[screen.data.level].offset.x * hex_col_mult
 y_pan = puzzles[screen.data.level].offset.y * hex_height
 screen.data.hexes = puzzles[screen.data.level].hexes
 for_all_hexes(fill_n)
 if puzzles[screen.data.level].solved then
  reveal_all()
 end
 _, screen.data.bombs_left = puzzle_status()
 screen.data.bees={} -- todo: beesplosion

 -- easy but hilariously hacky
 screen.data.h_color_func = function ()
  local mapping = {[0]=8, [3]=3}
  return mapping[stat(16)]
 end
end

function _update_puzzle(curr_x, curr_y, curr_mouse, scroll)
 -- zoom
 local new_side_length = hex_side_length + scroll
 if new_side_length >= 8 and new_side_length <= 16 then
  update_hex_side_length(new_side_length)
 end

 local hex = hovered_hex(curr_x, curr_y, curr_mouse)

 -- click
 if hex != nil and not hex.revealed then
  if curr_mouse == 1 then
   if hex.bomb then
    osfx(0, 0)
   else
    osfx(3, 0)
    hex.revealed = true
   end
  end

  if curr_mouse == 2 then
   if hex.bomb then
    osfx(3, 0)
    hex.revealed = true
   else
    osfx(0, 0)
   end
  end
 end

 -- pan
 if hex == nil and last_mouse.v != 0 and curr_mouse != 0 then
  x_pan += curr_x - last_mouse.x
  y_pan += curr_y - last_mouse.y
 end
 
 -- level select
 if hex == nil and curr_mouse == 2 then
  switch_screen(level_select)
  return
 end

 if not puzzles[screen.data.level].solved then
  local all_solved
  all_solved, screen.data.bombs_left = puzzle_status()

  if all_solved then
   set_solved(screen.data.level)
   sfx(2, 0)
  end

 end
end

function _draw_puzzle()
 draw_hexes(true)

 local width = 51
 if screen.data.bombs_left > 9 then
  width += 4
 end
 text("bombs left: "..screen.data.bombs_left, 5, 5, width, 5)

 if puzzles[screen.data.level].solved then
  text("solved!", 96, 5, 26, 5)
 end

 if screen.data.level == 1 then
  text("mouse 1: hex is empty", 25, 90, 83, 5)
  text("mouse 2: hex is bomb", 27, 100, 79, 5)
  text("click + drag to pan", 29, 110, 75, 5)
  text("scroll to zoom", 39, 120, 55, 5)
 end
end

puzzle = screenm(_init_puzzle, _update_puzzle, _draw_puzzle)
-- end: puzzle

-- utility functions

-- switch to a new screen
-- whichever update calls this doesn't call the update of the new screen, meaning
-- update(screen a update, switch b, screen b init) draw(screen b draw)
-- meaning on switch, the new screen gets a draw call without an update call
-- meaning init must truly handle any init stuff, otherwise there will be a flicker between frame 0 and 1 of screen b
function switch_screen(new_screen, args)
 local old_screen = screen

 waiting_for_let_go = true

 screen = new_screen
 screen.data = {}
 if args != nil then
  for k, v in pairs(args) do
   screen.data[k] = v
  end
 end
 screen.init()

 -- on first switch ever, don't do an animatio and just show the main menu
 --if switching == nil then
 --  switching = false
 --else
  switching = true
  switch.data = {}
  switch.init()

  osfx(1, 0)
 --end
end

-- create horizontal line of bees with some random y offsets
function line_of_bees()
 local bees, x = {}, 0
 while x < 128 do
  bees[#bees + 1] = {x=x, y=rnd(4) - 2}
  x += rnd(4) + 4
 end

 return bees
end

-- beesplosion
function beesplosion()
 local bees = {}
end

-- gets metadata on puzzle completion
function puzzle_status()
 local all_solved, bombs_left = true, 0
 
 for_all_hexes(function (hex)
  if not hex.revealed then
   all_solved = false
   if hex.bomb then
    bombs_left += 1
   end
  end
 end)

 return all_solved, bombs_left
end

function reveal_all()
 for_all_hexes(function (hex)
  hex.revealed = true
 end)
end

-- draws text with a rectangle behidn it for readability
function text(text, x, y, width, c)
 rectfill(x - 1, y - 1, x + width, y + 5, 10)
 print(text, x, y, c)
end


-- plays sfx n on channel c if nothing else is playing on channel c
function osfx(n, c)
 if stat(16 + c) == -1 then
  sfx(n, c)
 end
end

-- creates a hex
function hexm(col, row, bomb, revealed)
  if revealed == nil then revealed = false end
  if bomb == nil then bomb = false end
  
  -- 7 on purpose, n is supposed to be set properly once the puzzle is generated
  return {col=col, row=row, n=7, bomb=bomb, revealed=revealed}
 end

-- runs a function on all hexes
function for_all_hexes(func)
 for col, rows in ipairs(screen.data.hexes) do
  for row, hex in ipairs(rows) do
   if hex != no_hex then
    func(hex)
   end
  end
 end
end


-- adjacent hex offsets, using odd-q vertical coordinates
-- first index is for even cols, second for odd cols
adj = {
 {{x=-1,y=-1},{x=0,y=-1},{x=1,y=-1},{x=-1,y=0},{x=0,y=1},{x=1,y=0}},
 {{x=-1,y=0},{x=0,y=-1},{x=1,y=0},{x=-1,y=1},{x=0,y=1},{x=1,y=1}}
}

-- sets the proper n for a puzzle
function fill_n(hex)
 local sum = 0
 for _, offset in ipairs(adj[(hex.col % 2) + 1]) do
  local row = screen.data.hexes[hex.col + offset.x]
  if row != nil then
   local hexy = row[hex.row + offset.y]
   if hexy != nil and hexy != no_hex and hexy.bomb then
    sum += 1
   end
  end
 end

 hex.n = sum
end

-- returns the hex being hovered over, and saves the points of that hex to a global
function hovered_hex(curr_x, curr_y, curr_mouse)
 local new_highlight_hex = nil
 local new_highlight_p = nil

 for_all_hexes(
  function (hex)
   local c_x, c_y, points = hex_points(hex.col, hex.row)
   if hex_contains(points, c_x, c_y, curr_x, curr_y) then
    new_highlight_hex = hex
    new_highlight_p = points
   end
  end
 )

 -- if click and hold, keep hovered hex as what was held on so you can't click/drag
 if highlight_hex != nil then

  if curr_mouse == 0 then
   highlight_hex = new_highlight_hex
   screen.data.highlight_p = new_highlight_p
  end

 else
  highlight_hex = new_highlight_hex
  screen.data.highlight_p = new_highlight_p
 end

 return highlight_hex
end

-- draws all hexes
function draw_hexes(highlight)
 for_all_hexes(draw_hex)

 if highlight then
  draw_hex_highlight()
 end
end

-- changes the side length of a hex
function update_hex_side_length(new_hex_side_length)
 hex_side_length = new_hex_side_length
 hex_height = sqrt(3) * hex_side_length
 hex_width = 2 * hex_side_length
 hex_col_mult = 1.5 * hex_side_length
end

-- returns the points that make up a hexagon at the given position (first point repeated)
function hex_points(c, r)
 local center_x, center_y = pixel_pos(c, r)

 local points = {}

 for angle=0, 5 do
  local x_offset = hex_side_length * sin(angle / 6 + 1 / 12)
  local y_offset = hex_side_length * cos(angle / 6 + 1 / 12)

  local x=round(center_x + x_offset)
  local y=round(center_y + y_offset)
  points[#points + 1] = {x=x, y=y}
 end

 points[#points + 1] = points[1]

 return center_x, center_y, points
end

-- draws a hex
function draw_hex(hex)
 local center_x, center_y, points = hex_points(hex.col, hex.row)

 -- edges
 for i=1, #points - 1 do
  line(points[i].x, points[i].y, points[i + 1].x, points[i + 1].y, 9)
 end
 
 -- center
 if hex.revealed then

  -- bomb
  if hex.bomb then
   circfill(center_x + 0.5, center_y + 0.5, hex_side_length / 2, 14)
  else
   -- number
   local x_off = 1
   if hex.n > 9 then
    x_off = hex_side_length / 4
   end

   local coloor = 5
   if screen.data.color_func != nil and screen.data.color_func(hex) != nil then
    coloor = screen.data.color_func(hex)
   end
   print(hex.n, center_x - x_off, center_y - hex_side_length / 8, coloor)
  end
 end
end

-- redraws a hex edges, using points created by hovered_hex
function draw_hex_highlight()
 local highlight_p = screen.data.highlight_p

 if highlight_p != nil then
  for i=1, #highlight_p - 1 do
    local coloor = 6
    if screen.data.h_color_func != nil and screen.data.h_color_func() != nil then
     coloor = screen.data.h_color_func()
    end
    line(highlight_p[i].x, highlight_p[i].y, highlight_p[i + 1].x, highlight_p[i + 1].y, coloor)
  end
 end
end

-- returns a value between v0 and v1 given t (between 0 and 1)
function lerp(v0, v1, t)
 return (1 - t) * v0 + t * v1
end

-- returns the pixel position of the center of the hexagon position at index col, row using odd-q offset coordinates
function pixel_pos(c, r)
 local center_x, center_y = c * hex_col_mult + x_pan, r * hex_height + y_pan --+ t, + (t/(hex_side_length * 3)) * sqrt(3) * hex_side_length

 if c % 2 == 1 then
  center_y += hex_height / 2
 end

 return center_x, center_y
end

-- returns whether the hex defined by the given points and center contains the other point
function hex_contains(points, c_x, c_y, x, y)
 -- a point p is within a hex if for every edge of the hexagon it's on the same side of that line as the center point
 -- this works because we know the center point to be in the hex; any point inside the hex would work as well

 for i=1, #points - 1 do
   -- create line that represents the current edge
   local f = create_line(points[i].x, points[i].y, points[i + 1].x, points[i + 1].y)

   -- f(x) - y is the distance from the point to the line (going straight up/down)
   -- the sign of that is either positive if the point is above the line, or negative if the point is below the line
   local side_center, side_point = sgn(f(c_x) - c_y), sgn(f(x) - y)
   
   -- sides not same -> outside hex
   if side_point != side_center then
    return false
   end
 end

 -- sides all same -> in hex
 return true
end

-- returns a line that goes through the given points
function create_line(x0, y0, x1, y1)
 local slope = (y1 - y0) / (x1 - x0)
 local offset = y1 - slope * x1

 return function(x)
  return slope * x + offset
 end
end

-- rounds v to the nearest whole number
function round(v)
 return flr(v + 0.5)
end

-- reads completion data from cart
function load_save()
 for i=1, 16 do
  if puzzles[i] != nil then
   puzzles[i].solved = dget(i - 1) == 1
  end
 end
end

function set_solved(puzzle_num)
 dset(puzzle_num - 1, 1)
 puzzles[puzzle_num].solved = true
end

-- end: utility functions

-- puzzle info
puzzles ={
 {
  offset={x=1.5, y=0.5},
  size=12,
  hexes={{hexm(1,1,false),hexm(1,2,false)},{hexm(2,1,false),hexm(2,2,false,true),hexm(2,3,false)},{hexm(3,1,false),hexm(3,2,false)}}
 },
 {
  offset={x=1.5, y=0.5},
  size=12,
  hexes={{hexm(1,1,true,true),hexm(1,2,false)},{hexm(2,1,false),hexm(2,2,false,true),hexm(2,3,false)},{hexm(3,1,false),hexm(3,2,false)},{no_hex, no_hex, hexm(4,3,true)}}
 },
 {
  offset={x=0.75, y=0},
  size=12,
  hexes={{hexm(1,1,true,true),hexm(1,2,false,true),hexm(1,3,false),hexm(1,4,false)},{no_hex, no_hex, no_hex, no_hex, hexm(2,5,false)},{no_hex, no_hex, no_hex, no_hex, hexm(3,5,true), hexm(3,6,false), hexm(3,7,false)},{no_hex, no_hex, no_hex, no_hex, hexm(4,5,false)},{hexm(5,1,true,true),hexm(5,2,false,true),hexm(5,3,false),hexm(5,4,false)}}
 }
}

__gfx__
00000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
00000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
00000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
00000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
00000000000aaaaaaa9999999aaaaaaaaaaaaaaaaaaaaaa9999999999aaaaaaaaaaaaaaaaaaaaaa999999999a999aaaaaaaaa999aaaaaaaaaaaaaaaaaaaaaaaa
00000000000aaaaa99999999999aaaaaaa99999999999aa9999999999aaaaaaaaa99999999aaaaa999999999a999aaaaaaaaa999aaaaaaaaaaa99999999aaaaa
00000000000aaaaa999999999999aaaaaa99999999999aa9999999999aaaaaaaa999999999aaaaa999aaaaaaa999aaaaaaaaa999aaaaaaaaa9999999999aaaaa
00000000000aaaaa9999aaa999999aaaaa99999999999aa9999aaaaaaaaaaaaa9999999999aaaaa999aaaaaaa999aaaaaaaaa999aaaaaaaa99999999999aaaaa
00000000000aaaaa9999aaaaa9999aaaaa999aaaaaaaaaa9999aaaaaaaaaaaaa99999aaaaaaaaaa999aaaaaaa999aaaaaaaaa999aaaaaaaa999999aaaaaaaaaa
00000000000aaaaa9999aaaaaa9999aaaa999aaaaaaaaaa9999aaaaaaaaaaaa9999aaaaaaaaaaaa999aaaaaaa999aaaaaaaaa999aaaaaaa99999aaaaaaaaaaaa
00000000000aaaaa9999aaaaaa9999aaaa999aaaaaaaaaa9999aaaaaaaaaaaa9999aaaaaaaaaaaa999aaaaaaa999aaaaaaaaa999aaaaaaa9999aaaaaaaaaaaaa
00000000000aaaaa9999aaaaaaa999aaaa999aaaaaaaaaaa999aaaaaaaaaaaa999aaaaaaaaaaaaa999aaaaaaa999aaaaaaaaa999aaaaaaa9999aaaaaaaaaaaaa
00000000000aaaaaa999aaaaaaa999aaaa999aaaaaaaaaaa999aaaaaaaaaaa9999aaaaaaaaaaaaa999aaaaaaa999aaaaaaaaa999aaaaaaa99999aaaaaaaaaaaa
00000000000aaaaaa999aaaaaa9999aaaa999aaaaaaaaaaa999aaaaaaaaaaa9999aaaaaaaaaaaaa999aaaaaaa999aaaaaaaaa999aaaaaaa999999999aaaaaaaa
00000000000aaaaaa999aa99999999aaaa999aaaaaaaaaaa999aa99999aaaa999aaaaaaaaaaaaaa999aaaaaaa999aaaaaaaaa999aaaaaaa99999999999aaaaaa
00000000000aaaaaa999999999999aaaaa9999999999aaaa9999999999aaaa999aaaaaaaaaaaaaa99999999aa999aaaaaaaaa999aaaaaaaaa999999999aaaaaa
00000000000aaaaaa999999999999aaaaa9999999999aaaa9999999999aaaa999aaaaaaaaaaaaaa99999999aa999aaaaaaaaa999aaaaaaaaaaaaa999999aaaaa
00000000000aaaaaa99999999999999aaa9999999999aaaa99999999aaaaaa999aaaaaaaaaaaaaa99999999aa999aaaaaaaaa9999aaaaaaaaaaaaaa9999aaaaa
00000000000aaaaa999999999999999aaa999aaaaaaaaaaa9999aaaaaaaaaa999aaaaaaaaaaaaaa999aaaaaaa999aaaaaaaaa9999aaaaaaaaaaaaaa9999aaaaa
00000000000aaaaa9999aaaaaa99999aaa999aaaaaaaaaaa9999aaaaaaaaaa999aaaaaaaaaaaaaa999aaaaaaa999aaaaaaaaaa999aaaaaaaaaaaaaaa999aaaaa
00000000000aaaaa9999aaaaaaaa999aaa999aaaaaaaaaaa9999aaaaaaaaaa9999aaaaaaaaaaaaa999aaaaaaa999aaaaaaaaaa999aaaaaaaaaaaaaaa999aaaaa
00000000000aaaaa999aaaaaaaa9999aaa999aaaaaaaaaaaa999aaaaaaaaaa99999aaaaaaaaaaaa999aaaaaaa999aaaaaaaaaa999aaaaaaaaaaaaaa9999aaaaa
00000000000aaaaa999aaaaaaaa9999aaa999aaaaaaaaaaaa999aaaaaaaaaa999999aaaaaaaaaaa999aaaaaaa999aaaaaaaaaa999aaaaaaaaaaaaa99999aaaaa
00000000000aaaaa999aaaaaaa99999aaa999aa9999aaaaaa999aa99999aaaa9999999aaaaaaaaa99999999aa999aaaaaaaaaa999aaaaaaaaaaaa999999aaaaa
00000000000aaaaa9999aaa9999999aaaa999999999aaaaaa9999999999aaaaa999999999999aaa99999999aa9999999999aaa999aa999aa9999999999aaaaaa
00000000000aaaaa9999999999999aaaaa999999999aaaaaa9999999999aaaaaa99999999999aaa99999999aa9999999999aaa99999999aa999999999aaaaaaa
00000000000aaaaa999999999999aaaaaa99999999aaaaaaa99999999aaaaaaaaaa999999999aaaaaaaaaaaaa9999999999aaa99999999aa99999999aaaaaaaa
00000000000aaaaaa99999999aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa99999999aaaaaaaaaaaaaaaaaa
00000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
00000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
00000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
00000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
00000f0f111040000fff000000000000000000000000000000022200000000000000000000000000000000000000000000000000000000000000000000000000
94949f9f110044000f4f000022222200220002200000000000222200000000000000220000000000000000000000000000000000000000000000000000000000
8999894410000949999ffff022222220222002200000000002222200000000000000220000000000000000000000000000000000000000000000000000000000
99999944000009999999f4f022002220222002200000000022200000000000000000220000000000000000000000000000000000000000000000000000000000
44994449400999499999f4f022002220222202200000000022000000000000000000220000000000000000000000000000000000000000000000000000000000
4444449904499999999999f022222200222222200000000222000000022222000022222200000000000000000000000000000000000000000000000000000000
99449994009999999999994022222220002222200000002220000000222222000022222200000000000000000000000000000000000000000000000000000000
09999944009499499999994022000222000222000000002200000000222022200000220000000000000000000000000000000000000000000000000000000000
00000000009994499999944922000222000022000000002200000002220022220000220000000000000000000000000000000000000000000000000000000000
00000000009999999999949422000022000222000000002200000002200002222000220000000000000000000000000000000000000000000000000000000000
00000000009999999999449422000222000220000000002200000002200022222200220000000000000000000000000000000000000000000000000000000000
00000000009999999994494022222222002220000000002200000002200222222220220000000000000000000000000000000000000000000000000000000000
00000000000999999444944002222220022200000000002220022222222222002220220000000000000000000000000000000000000000000000000000000000
00000000000009994499444000000000022200000000002222222220222220000220220000000000000000000000000000000000000000000000000000000000
00000000000000994944000400000000000000000000000022220000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000900000707001700070700370017600187001a7001d6001c7001d700216001f7001f7001f7002d7001e7001e7001d7001c7001b5001c50020400224002240027300293002c3001700017000170001700017000
001000001a11000500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000400002475424750247502475026750267502675026750287502875028750287502875029750297502975029750297551e7001f747217472374724747267051d7001f757217572375724757267051f00420700
000600002204000000260400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000f05000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
