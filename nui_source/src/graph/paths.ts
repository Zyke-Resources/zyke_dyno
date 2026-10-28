import type { Curve } from "../types";
import { rpmAt } from "./units";

export interface Frame {
    width: number;
    height: number;
    minRpm: number;
    maxRpm: number;
    maxPower: number;
    maxTorque: number;
}

export interface Point {
    x: number;
    y: number;
}

export const toX = (frame: Frame, rpm: number) => ((rpm - frame.minRpm) / (frame.maxRpm - frame.minRpm)) * frame.width;

// The points of one series of a curve, already in the display unit, up to revealed points (fractional while the
// pull is on, so the line grows smoothly between two points)
export const getPoints = (frame: Frame, curve: Curve, values: number[], top: number, revealed = values.length): Point[] => {
    const count = values.length;
    const whole = Math.min(Math.floor(revealed), count);
    const points: Point[] = [];
    const toY = (value: number) => frame.height - (value / top) * frame.height;

    for (let i = 0; i < whole; i++) {
        points.push({ x: toX(frame, rpmAt(curve.startRpm, curve.redline, count, i)), y: toY(values[i]) });
    }

    const part = revealed - whole;

    if (part > 0 && whole > 0 && whole < count) {
        const from = values[whole - 1];
        const rpm = rpmAt(curve.startRpm, curve.redline, count, whole - 1 + part);

        points.push({ x: toX(frame, rpm), y: toY(from + (values[whole] - from) * part) });
    }

    return points;
};

// Slope of the line through a point from the slopes on either side of it. Flat at a peak or a dip, so the line
// never bends past the points around it and the highest point drawn is the peak on the sheet
const getTangent = (before: number, after: number) => (before * after <= 0 ? 0 : (2 * before * after) / (before + after));

// A smooth line through the points, as dyno software draws its traces
export const toPath = (points: Point[]) => {
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
};
