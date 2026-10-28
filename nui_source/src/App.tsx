import { useEffect } from "react";
import { postNui } from "./nui";
import ScreenGrid from "./screen/ScreenGrid";
import Printout from "./sheet/Printout";
import { useDyno } from "./state/useDyno";

// The DUI on the dyno screens opens this page with ?screen=1, and how many tiles it holds in how many columns
const query = new URLSearchParams(window.location.search);
const isScreen = query.has("screen");
const slots = Math.max(1, Number(query.get("slots")) || 1);
const columns = Math.max(1, Number(query.get("columns")) || 1);

// What zyke_dyno draws: on the screen the run and the last result, and over the game a printed result shown to the
// player. The key panel is zyke_lib's. It never takes focus, so the game keeps its input
const App = () => {
    const dyno = useDyno();

    // Lua sends the words again once the page can take them
    useEffect(() => {
        if (isScreen) return;

        postNui("Ready");
    }, []);

    if (isScreen) return <ScreenGrid slots={slots} columns={columns} />;

    return <Printout sheet={dyno.sheet} labels={dyno.labels} units={dyno.units} />;
};

export default App;
