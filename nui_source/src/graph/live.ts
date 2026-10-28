import type { Curve } from "../types";

export interface LiveValues {
    power: number;
    torque: number;
    peakPower: number;
    peakTorque: number;
}

// The power and torque at the head of the line, and the highest of each so far, in kW and Nm
export const getLiveValues = (curve: Curve, revealed: number): LiveValues => {
    const count = curve.power.length;
    const whole = Math.max(1, Math.min(Math.floor(revealed), count));
    const part = Math.min(revealed - whole, 1);
    const next = Math.min(whole, count - 1);
    const lerp = (values: number[]) => values[whole - 1] + (values[next] - values[whole - 1]) * Math.max(part, 0);
    const shown = (values: number[]) => values.slice(0, whole);

    return {
        power: lerp(curve.power),
        torque: lerp(curve.torque),
        peakPower: Math.max(...shown(curve.power)),
        peakTorque: Math.max(...shown(curve.torque)),
    };
};

export const formatNumber = (value: number, digits = 0) => value.toFixed(digits);
