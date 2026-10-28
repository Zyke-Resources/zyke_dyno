import type { Curve, Units } from "../types";
import type { Frame } from "./paths";
import { getPoints, toPath } from "./paths";
import { toPower, toTorque } from "./units";
import styles from "./DynoGraph.module.css";

interface SeriesProps {
    frame: Frame;
    curve: Curve;
    units: Units;
    // Points drawn so far, all of them when left out
    revealed?: number;
    // "live" for this run, "previous" and "first" for the runs it is laid over
    kind: "live" | "previous" | "first";
}

// The power and torque lines of one run, with a dot at the head of the lines while they are still drawn
const Series = ({ frame, curve, units, revealed, kind }: SeriesProps) => {
    const power = getPoints(frame, curve, curve.power.map((kw) => toPower(kw, units.power)), frame.maxPower, revealed);
    const torque = getPoints(frame, curve, curve.torque.map((nm) => toTorque(nm, units.torque)), frame.maxTorque, revealed);
    const growing = kind === "live" && revealed !== undefined && revealed < curve.power.length;
    const head = power[power.length - 1];
    const torqueHead = torque[torque.length - 1];

    return (
        <g className={styles[kind]}>
            <path className={`${styles.line} ${styles.torqueLine}`} d={toPath(torque)} />
            <path className={`${styles.line} ${styles.powerLine}`} d={toPath(power)} />
            {growing && head && <circle className={styles.powerHead} cx={head.x} cy={head.y} r={7} />}
            {growing && torqueHead && <circle className={styles.torqueHead} cx={torqueHead.x} cy={torqueHead.y} r={6} />}
        </g>
    );
};

export default Series;
