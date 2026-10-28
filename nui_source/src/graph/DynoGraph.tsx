import type { Compare, Curve, Labels, Units } from "../types";
import Axes from "./Axes";
import Series from "./Series";
import { getFrame } from "./frame";
import styles from "./DynoGraph.module.css";

interface DynoGraphProps {
    curve: Curve;
    compare?: Compare;
    units: Units;
    labels: Labels;
    revealed?: number;
    width: number;
    height: number;
}

const margin = { top: 34, right: 64, bottom: 56, left: 64 };

// The dyno sheet's graph: power and torque against rpm, this run over the car's last run and its first
const DynoGraph = ({ curve, compare, units, labels, revealed, width, height }: DynoGraphProps) => {
    const others = [compare?.first?.curve, compare?.previous?.curve].filter((other): other is Curve => Boolean(other));
    const frame = getFrame([curve, ...others], units, width - margin.left - margin.right, height - margin.top - margin.bottom);

    return (
        <svg className={styles.graph} width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
            <g transform={`translate(${margin.left}, ${margin.top})`}>
                <Axes frame={frame} powerLabel={labels[units.power] ?? units.power} torqueLabel={labels[units.torque] ?? units.torque} rpmLabel={labels.rpm ?? "rpm"} />
                {compare?.first?.curve && <Series frame={frame} curve={compare.first.curve} units={units} kind="first" />}
                {compare?.previous?.curve && <Series frame={frame} curve={compare.previous.curve} units={units} kind="previous" />}
                <Series frame={frame} curve={curve} units={units} revealed={revealed} kind="live" />
            </g>
        </svg>
    );
};

export default DynoGraph;
