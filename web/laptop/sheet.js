// A result sheet with the same numbers as the one the driver gets in game: the peaks at the wheels with the rpm they
// peak at, the engine's power and the drivetrain loss, the drivetrain, and the gain over the car's last run
import { drawGraph, curvePoints } from "./graph.js";
import { t, el, whole, speedText, powerText, torqueText, atRpm, formatDate } from "./page.js";

function stat(label, value, note, tone) {
    return el("div", { class: "stat" }, el("span", { class: "stat-label", text: label }), el("span", { class: `stat-value ${tone || ""}`, text: value }), note && el("span", { class: "stat-note", text: note }));
}

// Which line is which: this run, the car's last run and its first
export function legend(compare, thisLabel = t("nui:thisRun")) {
    const entry = (kind, label) => el("span", { class: "legend-entry" }, el("span", { class: `swatch ${kind}` }), label);

    return el("div", { class: "legend" }, entry("this", thisLabel), compare?.previous && entry("previous", t("nui:previous")), compare?.first && entry("first", t("nui:first")));
}

function gainStat(sheet) {
    // Saved runs from the history carry no comparison, so their gain is not known here
    if (!sheet.gain && !sheet.compare) return null;
    if (!sheet.gain) return stat(t("nui:gain"), t("nui:noGain"), null, "gain");

    const sign = sheet.gain.wheelKw >= 0 ? "+" : "-";

    return stat(t("nui:gain"), `${sign}${powerText(Math.abs(sheet.gain.wheelKw))}`, null, sheet.gain.wheelKw < 0 ? "loss" : "gain");
}

// actions are extra buttons under the title, such as every run of this car
export function renderSheet(container, sheet, actions = []) {
    const drive = sheet.redlineSpeed ? speedText(sheet.redlineSpeed) : null;
    const graph = el("div", { class: "graph-box" });

    container.replaceChildren(
        el(
            "div",
            { class: "sheet" },
            el(
                "div",
                { class: "sheet-top" },
                el("span", { class: "sheet-title", text: t("nui:sheetTitle") }),
                el("span", { class: "sheet-car", dir: "auto" }, sheet.label, " ", el("span", { class: "plate", text: sheet.plate })),
                el("span", { class: "sheet-date", text: sheet.date ? formatDate(sheet.date) : "" }),
                actions
            ),
            el(
                "div",
                { class: "stats" },
                stat(`${t("nui:peakPower")} · ${t("nui:wheel")}`, powerText(sheet.wheelKw), atRpm(sheet.powerRpm), "power"),
                stat(`${t("nui:peakTorque")} · ${t("nui:wheel")}`, torqueText(sheet.wheelNm), atRpm(sheet.torqueRpm), "torque"),
                stat(t("nui:engine"), powerText(sheet.engineKw), `${t("nui:loss")} ${whole((sheet.loss ?? 0) * 100)}%`),
                stat(t("nui:drivetrain"), sheet.drive, drive && sheet.gear ? `${drive} · ${t("nui:gear")} ${sheet.gear}` : drive),
                gainStat(sheet)
            ),
            graph,
            legend(sheet.compare)
        )
    );

    drawGraph(graph, { points: curvePoints(sheet.curve), compare: sheet.compare });
}