import type { PowerUnit, SpeedUnit, TorqueUnit, Units } from "../types";

const kwPerUnit: Record<PowerUnit, number> = { hp: 0.7457, ps: 0.735499, kw: 1 };
const nmPerUnit: Record<TorqueUnit, number> = { nm: 1, lbft: 1.355818 };

export const defaultUnits: Units = { power: "hp", torque: "nm", speed: "kmh" };

export const toPower = (kw: number, unit: PowerUnit) => kw / kwPerUnit[unit];

export const toTorque = (nm: number, unit: TorqueUnit) => nm / nmPerUnit[unit];

// Metres a second to the speed unit
export const toSpeed = (metres: number, unit: SpeedUnit) => (unit === "mph" ? metres * 2.236936 : metres * 3.6);

// The rpm of a curve's point, which are spread evenly from the start of the pull to the redline
export const rpmAt = (startRpm: number, redline: number, count: number, index: number) =>
    startRpm + ((redline - startRpm) * index) / Math.max(count - 1, 1);

// A round number at or above value for the top of an axis, such as 350 for 312
export const niceCeiling = (value: number) => {
    const step = Math.pow(10, Math.floor(Math.log10(Math.max(value, 1)))) / 2;

    return Math.ceil(value / step) * step;
};
