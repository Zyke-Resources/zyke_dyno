export type PowerUnit = "hp" | "ps" | "kw";
export type TorqueUnit = "nm" | "lbft";
export type SpeedUnit = "kmh" | "mph";

export interface Units {
    power: PowerUnit;
    torque: TorqueUnit;
    speed: SpeedUnit;
}

// A run's curve as shared/formula.lua works it out: wheel kW and Nm at points spread evenly from startRpm to redline
export interface Curve {
    startRpm: number;
    redline: number;
    power: number[];
    torque: number[];
}

// A finished run, as server/results.lua builds it and the database keeps it
export interface Sheet {
    plate: string;
    label: string;
    model: string;
    drive: string;
    date: number;
    engineKw: number;
    wheelKw: number;
    wheelNm: number;
    powerRpm: number;
    torqueRpm: number;
    loss?: number;
    redlineSpeed?: number;
    gear?: number;
    curve: Curve;
    compare?: Compare;
    gain?: { wheelKw: number; wheelNm: number };
}

export interface Compare {
    previous?: Sheet;
    first?: Sheet;
}

export interface RunPayload {
    dynoId: number;
    label: string;
    plate: string;
    drive: string;
    curve: Curve;
    compare?: Compare;
    units: Units;
}

export type Phase = "ready" | "pull" | "limiter" | "coast";

// Where the driver's pull stands. revealed counts the points of the curve drawn so far, which only grows while the
// throttle is held flat
export interface ProgressPayload {
    dynoId: number;
    revealed: number;
    rpm: number;
    phase: Phase;
    // Already in the configured unit
    speed: number;
    // Wheel kW and Nm the engine makes this moment, with the throttle as it is
    power: number;
    torque: number;
    throttle: number;
    gear: number;
}

export type Labels = Record<string, string>;

export interface LuaMessages {
    Labels: { labels: Labels; units: Units };
    Run: RunPayload;
    Progress: ProgressPayload;
    RunEnd: Record<string, never>;
    Standby: { last?: Sheet };
    Sheet: Sheet | Record<string, never>;
}
