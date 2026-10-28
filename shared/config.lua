Config = Config or {}

Config.Settings = {
    dyno = {
        -- Units on the screen, the result sheet and the logs: "hp", "ps" or "kw" for power, "nm" or
        -- "lbft" for torque, "kmh" or "mph" for speed
        units = {power = "hp", torque = "nm", speed = "kmh"},
        -- Default keys. Players change them under Settings > Key Bindings > FiveM, and a changed default only reaches
        -- players who did not have the key yet. The placing tool's mouse buttons and scroll wheel, and Backspace to
        -- stop a run or close a sheet, are the game's own controls
        keys = {
            startRun = "E",
            -- At a dyno's screen, while interaction below is "point"
            printSheet = "E",
            -- The placing tool, see admin below
            placeLine = "C",
            placeScreen = "Q",
            placeKind = "TAB",
            placeMode = "Z",
        },
        -- How a vehicle's handling and mods become its power, see shared/formula.lua. Run /dynocalibrate in a
        -- vehicle to print every input and the result, and change scale until your vehicles read what you want
        formula = {
            -- One global factor on every vehicle. 0.004436 puts most vanilla cars near their real counterparts
            scale = 0.004436,
            massExponent = 1.5,
            speedExponent = 4.0,
            -- Factors per vehicle class (GetVehicleClass), for classes GTA gives light masses, such as supercars and
            -- motorcycles
            classScale = {[7] = 1.4, [8] = 7.0},
            -- Factors on single models, by display name in lower case (GetDisplayNameFromVehicleModel, the model name
            -- for most vehicles), such as {sultan = 1.1} for 10% more. GTA's scooters are lighter still than its
            -- motorcycles; the Faggio Sport shows as "faggion" and the Faggio as "faggio"
            models = {faggio = 2.5, faggion = 2.5, faggio3 = 2.5, pizzaboy = 2.5},
        },
        -- Share of the engine's power lost before it reaches the rollers, by the wheels that drive, and by vehicle
        -- class over that: a motorcycle's chain loses less than a car's gearbox, shafts and differential
        drivetrainLoss = {FWD = 0.12, RWD = 0.15, AWD = 0.20, classes = {[8] = 0.10}},
        -- Engine speeds the pull runs between. Redlines by vehicle class, and by display name to override those
        rpm = {
            idle = 850,
            redline = 7000,
            classes = {[0] = 6800, [4] = 6200, [7] = 8500, [8] = 11000, [9] = 5800, [10] = 4500, [11] = 4500, [12] = 5500, [20] = 4000},
            -- The big twin cruisers and choppers rev far lower than the sport bikes class 8 is set for
            models = {
                avarus = 6000, cliffhanger = 6000, daemon = 6000, daemon2 = 6000, gargoyle = 6000, hexer = 6000,
                innovation = 6000, nightblade = 6000, sanctus = 6000, sovereign = 6000, wolfsbane = 6000, zombiea = 6000,
                zombieb = 6000, faggio = 8500, faggion = 8500, faggio3 = 8500, pizzaboy = 8500,
            },
        },
        -- The gear the pull runs in, one under the vehicle's top gear when it has no more gears than this. The driver
        -- holds the throttle flat from low revs to the limiter and the rollers spin up as the vehicle would pick up
        -- speed on the road in that gear
        gear = 4,
        pull = {
            -- Milliseconds a run may take before it is stopped without a result
            maxMs = 60000,
        },
        -- What differs between the kinds of dyno: "car" for cars and "bike" for motorcycles, set by kind in
        -- shared/dynos.lua, the CreateDyno export or the placing tool. Each takes:
        --   allowedClasses  Vehicle classes that may go on it (GetVehicleClass). Boats, helicopters, planes,
        --                   trains, bicycles and the like stand on neither
        --   lineUp          How far the vehicle may stand from where its front wheels go to start: metres along
        --                   and across, degrees off straight
        --   inertia         How heavy the rollers feel, as a share of the vehicle's mass. 1.0 pulls as long as the
        --                   vehicle takes to gain the same speed on the road, lower values make shorter pulls; the
        --                   numbers stay the same. A bike dyno's drum is far heavier than the bike, as on a real one
        --   screen          Where a dyno placed with the placing tool has its screen on its left, as in
        --                   shared/dynos.lua; the tool can put it on the right instead, mirrored, or leave it out
        kinds = {
            car = {
                allowedClasses = {0, 1, 2, 3, 4, 5, 6, 7, 9, 12},
                lineUp = {along = 0.18, across = 0.30, angle = 5.0},
                inertia = 1.0,
                screen = {offset = vec3(-2.3, 0.6, 0.0), heading = 225.0},
            },
            bike = {
                allowedClasses = {8},
                lineUp = {along = 0.12, across = 0.08, angle = 4.0},
                inertia = 2.0,
                screen = {offset = vec3(-1.3, 0.3, 0.0), heading = 225.0},
            },
        },
        -- The lowest engine health a run starts at, and where a running pull is stopped
        minEngineHealth = 300.0,
        -- Jobs that may run every dyno, nil for anyone. A dyno in shared/dynos.lua can have its own
        jobs = nil,
        -- Runs kept per plate in the database, oldest first out. 0 keeps every run
        historyPerPlate = 25,
        -- The result sheet as an item, printed at a dyno's screen by anyone whose job may run that dyno, from the last
        -- result the screen shows. A dyno without a screen prints where its screen would stand on its left. The item
        -- has to exist in your inventory; using it shows the sheet
        printout = {enabled = true, item = "dyno_sheet"},
        -- How players print at the screen:
        -- "point" marks it with a zyke_lib interest point and its key
        -- "target" lists it in the target menu instead, needs ox_target or qb-target and falls back to points without one
        interaction = "point",
        -- The screen on its pillar beside a dyno: its model, the metres its origin stands off the floor and the
        -- corners of its picture in the model's frame, top left, top right, bottom right and bottom left as seen
        -- from the front. Each player sees the runs on the four screens nearest them, each its own
        screen = {
            model = "zyke_dyno_screen",
            height = 0.0,
            face = {vec3(0.32, 0.1537, 1.6363), vec3(-0.32, 0.1537, 1.6363), vec3(-0.32, 0.2286, 1.2841), vec3(0.32, 0.2286, 1.2841)},
        },
        -- Metres from a dyno its props stand within, and its screen is drawn within
        streamDistance = 80.0,
        screenDistance = 15.0,
        -- Prints the inputs of the vehicle you sit in and the power the formula gives it, for tuning scale. Any
        -- one of the permissions allows it: an ACE, where "command" lets anyone with command access in, or on ESX a
        -- group name
        calibrate = {command = "dynocalibrate", permission = {"command", "admin", "superadmin", "owner"}},
        -- The Dyno app on zyke_laptop, added while that resource runs: a player picks a dyno, connects to it and
        -- follows its runs live, its last result and its history. It only reads and never starts or stops a run.
        -- Who may connect follows jobs above and each dyno's own. range is the metres the player at the laptop may
        -- stand from the dyno, nil for anywhere
        laptop = {enabled = true, range = nil},
        -- "/dynos" takes out a tool that places car and bike dynos where you aim, lined up with the dyno nearest to
        -- it or free, and saves them in the database through oxmysql, so they stand again after a restart. The same
        -- tool takes away the dynos placed with it. Where their screens stand is in kinds above. Any one of the
        -- permissions allows it: an ACE, where "command" lets anyone with command access in, or on ESX a group name
        admin = {
            enabled = true,
            command = "dynos",
            permission = {"command", "admin", "superadmin", "owner"},
        },
    },
}