// The dyno graph: power and torque against rpm, with the runs it is laid over dashed and dotted behind it. Every
// run is a list of {rpm, kw, nm} points; a saved sheet's curve is spread evenly from its start to its redline
import { t, toPower, toTorque, units } from "./page.js";

const svgNs = "http://www.w3.org/2000/svg";
const margin = { top: 30, right: 56, bottom: 46, left: 56 };
const steps = 5;

function svg(tag, attributes = {}, text) {
    const node = document.createElementNS(svgNs, tag);

    for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
    if (text !== undefined) node.textContent = text;

    return node;
}

// A saved sheet's curve as points
export function curvePoints(curve) {
    if (!curve || !curve.power) return [];

    const count = curve.power.length;

    return curve.power.map((kw, index) => ({
        rpm: curve.startRpm + ((curve.redline - curve.startRpm) * index) / Math.max(count - 1, 1),
        kw,
        nm: curve.torque[index],
    }));
}

// A round number at or above value for the top of an axis, such as 350 for 312
function niceCeiling(value) {
    const step = Math.pow(10, Math.floor(Math.log10(Math.max(value, 1)))) / 2;

    return Math.ceil(value / step) * step;
}

function getFrame(runs, range, width, height) {
    const all = runs.flat();
    const rpms = all.map((point) => point.rpm).concat(range ? [range.from, range.to] : []);

    return {
        width,
        height,
        minRpm: Math.floor(Math.min(...rpms, 9000) / 1000) * 1000,
        maxRpm: Math.ceil(Math.max(...rpms, 1000) / 500) * 500,
        maxPower: niceCeiling(Math.max(...all.map((point) => toPower(point.kw)), 50) * 1.12),
        maxTorque: niceCeiling(Math.max(...all.map((point) => toTorque(point.nm)), 50) * 1.12),
    };
}

const toX = (frame, rpm) => ((rpm - frame.minRpm) / Math.max(frame.maxRpm - frame.minRpm, 1)) * frame.width;

function axes(frame) {
    const group = svg("g");

    for (let row = 0; row <= steps; row++) {
        const y = frame.height - (frame.height * row) / steps;

        group.append(
            svg("line", { class: "grid", x1: 0, x2: frame.width, y1: y, y2: y }),
            svg("text", { class: "tick power", x: -8, y: y + 4, "text-anchor": "end" }, Math.round((frame.maxPower * row) / steps)),
            svg("text", { class: "tick torque", x: frame.width + 8, y: y + 4 }, Math.round((frame.maxTorque * row) / steps))
        );
    }

    for (let rpm = Math.ceil(frame.minRpm / 1000) * 1000; rpm <= frame.maxRpm; rpm += 1000) {
        const x = toX(frame, rpm);

        group.append(svg("line", { class: "grid", x1: x, x2: x, y1: 0, y2: frame.height }), svg("text", { class: "tick", x, y: frame.height + 18, "text-anchor": "middle" }, rpm / 1000));
    }

    group.append(
        svg("text", { class: "axis power", x: -8, y: -12, "text-anchor": "end" }, t(`unit:${units().power}`)),
        svg("text", { class: "axis torque", x: frame.width + 8, y: -12 }, t(`unit:${units().torque}`)),
        svg("text", { class: "axis", x: frame.width, y: frame.height + 38, "text-anchor": "end" }, `${t("nui:rpm")} x1000`)
    );

    return group;
}

// Slope of the line through a point from the slopes on either side of it. Flat at a peak or a dip, so the line
// never bends past the points around it and the highest point drawn is the peak on the sheet
function getTangent(before, after) {
    return before * after <= 0 ? 0 : (2 * before * after) / (before + after);
}

// A smooth line through the points, as dyno software draws its traces
function smoothPath(points) {
    if (points.length === 0) return "";

    const slopes = points.slice(1).map((point, index) => (point.y - points[index].y) / Math.max(point.x - points[index].x, 0.001));
    const tangents = points.map((_, index) => getTangent(slopes[index - 1] ?? slopes[index] ?? 0, slopes[index] ?? slopes[index - 1] ?? 0));
    let path = `M${points[0].x.toFixed(1)},${points[0].y.toFixed(1)}`;

    for (let i = 1; i < points.length; i++) {
        const from = points[i - 1];
        const to = points[i];
        const third = (to.x - from.x) / 3;

        path += ` C${(from.x + third).toFixed(1)},${(from.y + tangents[i - 1] * third).toFixed(1)} ${(to.x - third).toFixed(1)},${(to.y - tangents[i] * third).toFixed(1)} ${to.x.toFixed(1)},${to.y.toFixed(1)}`;
    }

    return path;
}

function series(frame, points, kind, head) {
    const group = svg("g", { class: `series ${kind}` });
    const path = (value, top) => smoothPath(points.map((point) => ({ x: toX(frame, point.rpm), y: frame.height - (value(point) / top) * frame.height })));

    group.append(svg("path", { class: "line torque-line", d: path((point) => toTorque(point.nm), frame.maxTorque) }), svg("path", { class: "line power-line", d: path((point) => toPower(point.kw), frame.maxPower) }));

    const last = points[points.length - 1];

    if (head && last) {
        group.append(
            svg("circle", { class: "head power-head", r: 5, cx: toX(frame, last.rpm), cy: frame.height - (toPower(last.kw) / frame.maxPower) * frame.height }),
            svg("circle", { class: "head torque-head", r: 4, cx: toX(frame, last.rpm), cy: frame.height - (toTorque(last.nm) / frame.maxTorque) * frame.height })
        );
    }

    return group;
}

// Draws into container at its size. range {from, to} keeps the rpm axis steady while a live run is still short
export function drawGraph(container, { points, compare, range, live }) {
    const width = Math.max(container.clientWidth, 320);
    const height = Math.max(container.clientHeight, 200);
    const first = curvePoints(compare?.first?.curve);
    const previous = curvePoints(compare?.previous?.curve);
    const frame = getFrame([points, first, previous], range, width - margin.left - margin.right, height - margin.top - margin.bottom);
    const root = svg("svg", { class: "graph", width, height, viewBox: `0 0 ${width} ${height}` });
    const body = svg("g", { transform: `translate(${margin.left}, ${margin.top})` });

    body.append(axes(frame));

    if (first.length) body.append(series(frame, first, "first"));
    if (previous.length) body.append(series(frame, previous, "previous"));

    body.append(series(frame, points, "this", live));
    root.append(body);
    container.replaceChildren(root);
}