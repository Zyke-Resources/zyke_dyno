import { getFrame } from "../graph/frame";
import { getPoints, toPath } from "../graph/paths";
import { toPower, toTorque } from "../graph/units";
import type { Labels, Units } from "../types";
import PrintGrid from "./PrintGrid";
import type { PrintRun } from "./print";
import { inks } from "./print";
import styles from "./Printout.module.css";

interface PrintGraphProps {
    runs: PrintRun[];
    units: Units;
    labels: Labels;
    width: number;
    height: number;
}

const margin = { top: 10, right: 58, bottom: 44, left: 58 };

// The printed graph: power solid and torque dashed against engine speed, each run in its own ink, the oldest under
const PrintGraph = ({ runs, units, labels, width, height }: PrintGraphProps) => {
    const frame = getFrame(runs.map((run) => run.sheet.curve), units, width - margin.left - margin.right, height - margin.top - margin.bottom);
    const powerLabel = `${labels.power} (${labels[units.power] ?? units.power})`;
    const torqueLabel = `${labels.torque} (${labels[units.torque] ?? units.torque})`;
    const rpmLabel = `${labels.engineSpeed} (${labels.rpm} x1000)`;

    return (
        <svg className={styles.graph} width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
            <g transform={`translate(${margin.left}, ${margin.top})`}>
                <PrintGrid frame={frame} powerLabel={powerLabel} torqueLabel={torqueLabel} rpmLabel={rpmLabel} />
                {[...runs].reverse().map(({ kind, sheet }) => {
                    const curve = sheet.curve;
                    const power = getPoints(frame, curve, curve.power.map((kw) => toPower(kw, units.power)), frame.maxPower);
                    const torque = getPoints(frame, curve, curve.torque.map((nm) => toTorque(nm, units.torque)), frame.maxTorque);

                    return (
                        <g key={kind} stroke={inks[kind]} className={kind === "live" ? styles.inkLive : styles.inkOld}>
                            <path className={styles.torqueInk} d={toPath(torque)} />
                            <path className={styles.powerInk} d={toPath(power)} />
                        </g>
                    );
                })}
            </g>
        </svg>
    );
};

export default PrintGraph;
