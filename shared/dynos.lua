-- The dynos that always stand, for as long as this resource runs. Dynos placed in game with "/dynos" are saved in
-- the database instead, see server/placed.lua. Each line here takes:
--   coords   The floor under where the front wheels stand: the middle of the front rollers on a car dyno, the
--            chock on a bike dyno
--   heading  Degrees, the way a vehicle's nose points on it; it drives on from behind
--   kind     "car" for a car dyno, the default, or "bike" for a motorcycle dyno
--   screen   The screen pillar beside it, offset in metres from coords (x across to the right, y along toward the
--            nose) and turned by heading degrees from the dyno's, such as {offset = vec3(-2.3, 0.6, 0.0), heading =
--            225.0}. Left out, the dyno has no screen
--   jobs     Who may run it, over Config.Settings.dyno.jobs
--   label    Its name in the laptop app, "Dyno 1" and so on when left out
-- The car bed wants 2.6 m of room across and 7.2 m along, ramps included, and the bike bed 1.0 m across and 4.6 m
-- along. Other resources add dynos with the CreateDyno export
---@type {coords: vector3, heading: number, kind?: DynoKind, screen?: {offset: vector3, heading: number}, jobs?: string[] | string, label?: string}[]
Config.Dynos = {
}