import { formatNumber } from "../graph/live";
import { toPower, toTorque } from "../graph/units";
import type { Labels, Sheet, Units } from "../types";

export type RunKind = "live" | "previous" | "first";

// One run on the printout: this one and those it is laid over, each in its own ink
export interface PrintRun {
    kind: RunKind;
    sheet: Sheet;
}

// Ink colours as a colour laser printer puts them on paper
export const inks: Record<RunKind, string> = {
    live: "#1d3f9c",
    previous: "#b3261e",
    first: "#2e7d32",
};

export const getRuns = (sheet: Sheet): PrintRun[] => {
    const runs: PrintRun[] = [{ kind: "live", sheet }];

    if (sheet.compare?.previous) runs.push({ kind: "previous", sheet: sheet.compare.previous });
    if (sheet.compare?.first) runs.push({ kind: "first", sheet: sheet.compare.first });

    return runs;
};

export const formatPower = (kw: number, units: Units, labels: Labels) => `${formatNumber(toPower(kw, units.power))} ${labels[units.power] ?? ""}`;

export const formatTorque = (nm: number, units: Units, labels: Labels) => `${formatNumber(toTorque(nm, units.torque))} ${labels[units.torque] ?? ""}`;

// The date and time a run was made, as the printer stamps it
export const formatDate = (unix: number) => {
    const date = new Date(unix * 1000);
    const pad = (value: number) => String(value).padStart(2, "0");

    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

// Fills the %s of a locale text in order
export const fill = (text: string | undefined, ...values: string[]) => values.reduce((filled, value) => filled.replace("%s", value), text ?? "");
