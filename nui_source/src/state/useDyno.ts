import { useState } from "react";
import { useNuiEvent } from "../nui";
import type { Labels, ProgressPayload, RunPayload, Sheet, Units } from "../types";
import { defaultUnits } from "../graph/units";

// Everything Lua sends the page, for the screen beside the dyno and the player's own screen alike. A tile of the screen
// page takes only what was sent to its slot
export const useDyno = (slot?: number) => {
    const [labels, setLabels] = useState<Labels>({});
    const [units, setUnits] = useState<Units>(defaultUnits);
    const [run, setRun] = useState<RunPayload | null>(null);
    const [progress, setProgress] = useState<ProgressPayload | null>(null);
    const [last, setLast] = useState<Sheet | null>(null);
    const [sheet, setSheet] = useState<Sheet | null>(null);

    useNuiEvent(
        "Labels",
        (data) => {
            setLabels(data.labels);
            setUnits(data.units);
        },
        slot,
    );

    useNuiEvent(
        "Run",
        (data) => {
            setRun(data);
            setUnits(data.units);
            setProgress(null);
        },
        slot,
    );

    useNuiEvent("Progress", setProgress, slot);

    // A Lua table with nothing in it may arrive as an empty array
    useNuiEvent(
        "Standby",
        (data) => {
            setLast(data?.last && "plate" in data.last ? data.last : null);
            setRun(null);
        },
        slot,
    );

    useNuiEvent("Sheet", (data) => setSheet(data && "plate" in data ? (data as Sheet) : null));

    return { labels, units, run, progress, last, sheet };
};
