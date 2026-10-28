import type { Curve, Units } from "../types";
import type { Frame } from "./paths";
import { niceCeiling, toPower, toTorque } from "./units";

// The axes that hold every curve drawn: this run's and the ones it is laid over
export const getFrame = (curves: Curve[], units: Units, width: number, height: number): Frame => {
    let minRpm = Infinity;
    let maxRpm = 0;
    let maxPower = 0;
    let maxTorque = 0;

    for (const curve of curves) {
        minRpm = Math.min(minRpm, curve.startRpm);
        maxRpm = Math.max(maxRpm, curve.redline);
        maxPower = Math.max(maxPower, ...curve.power.map((kw) => toPower(kw, units.power)));
        maxTorque = Math.max(maxTorque, ...curve.torque.map((nm) => toTorque(nm, units.torque)));
    }

    return {
        width,
        height,
        minRpm: Math.floor(minRpm / 1000) * 1000,
        maxRpm: Math.ceil(maxRpm / 500) * 500,
        maxPower: niceCeiling(maxPower * 1.12),
        maxTorque: niceCeiling(maxTorque * 1.12),
    };
};
