// The run on the connected dyno as the driver makes it: the graph drawing itself from the points recorded at full
// throttle, the rpm, power and torque now, the peaks so far, and the phase
import { drawGraph } from "./graph.js";
import { legend } from "./sheet.js";
import { t, el, whole, toPower, toTorque, units, speedText } from "./page.js";

function readout(label, value, unit, tone) {
    return el("div", { class: "readout" }, el("span", { class: "readout-label", text: label }), el("span", { class: `readout-value ${tone || ""}` }, value, el("span", { class: "readout-unit", text: unit })));
}

function phaseText(live) {
    return t(`laptop:phase:${live.ended || live.phase}`);
}

function side(live) {
    const points = live.points;
    const last = points[points.length - 1];
    // Points are only recorded at full throttle, so the figures now stand only while the car pulls
    const pulling = !live.ended && last && (live.phase === "pull" || live.phase === "limiter");
    const peak = (key) => (points.length ? Math.max(...points.map((point) => point[key])) : null);
    const powerUnit = t(`unit:${units().power}`);
    const torqueUnit = t(`unit:${units().torque}`);

    return el(
        "div",
        { class: "side" },
        readout(t("nui:rpm"), whole(live.ended ? 0 : live.rpm), ""),
        readout(t("nui:power"), pulling ? whole(toPower(last.kw)) : "-", powerUnit, "power"),
        readout(t("nui:torque"), pulling ? whole(toTorque(last.nm)) : "-", torqueUnit, "torque"),
        el(
            "div",
            { class: "peaks" },
            readout(t("nui:peakPower"), peak("kw") === null ? "-" : whole(toPower(peak("kw"))), powerUnit, "power"),
            readout(t("nui:peakTorque"), peak("nm") === null ? "-" : whole(toTorque(peak("nm"))), torqueUnit, "torque"),
            readout(t("laptop:speed"), speedText(live.ended ? 0 : live.speed), ""),
            readout(t("laptop:throttle"), whole((live.ended ? 0 : live.throttle) * 100), "%"),
            readout(t("nui:gear"), String(live.gear ?? "-"), "")
        ),
        legend(live.compare)
    );
}

export function renderLive(container, live) {
    if (!live) {
        return container.replaceChildren(el("div", { class: "empty" }, el("p", { class: "empty-title", text: t("laptop:waiting") }), el("p", { class: "dim", text: t("laptop:waitingHint") })));
    }

    const graph = el("div", { class: "graph-box" });

    container.replaceChildren(
        el(
            "div",
            { class: "live" },
            el(
                "div",
                { class: "live-top" },
                el("span", { class: "sheet-car", dir: "auto" }, live.label, " ", el("span", { class: "plate", text: live.plate })),
                el("span", { class: "badge", text: live.drive }),
                el("span", { class: `chip phase ${live.ended || live.phase}`, text: phaseText(live) })
            ),
            el("div", { class: "live-body" }, graph, side(live))
        )
    );

    drawGraph(graph, { points: live.points, compare: live.compare, range: { from: live.startRpm, to: live.redline }, live: !live.ended });
}