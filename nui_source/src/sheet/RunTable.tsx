import { formatNumber } from "../graph/live";
import type { Labels, Units } from "../types";
import type { PrintRun, RunKind } from "./print";
import { formatDate, formatPower, formatTorque, inks } from "./print";
import styles from "./Printout.module.css";

interface RunTableProps {
    runs: PrintRun[];
    units: Units;
    labels: Labels;
}

const runLabels: Record<RunKind, string> = { live: "thisRun", previous: "previous", first: "first" };

// The key under the graph: each run's ink with its date and peaks, as dyno software prints its run list
const RunTable = ({ runs, units, labels }: RunTableProps) => (
    <table className={styles.runs}>
        <thead>
            <tr>
                <th>{labels.run}</th>
                <th>{labels.date}</th>
                <th>{labels.maxPower}</th>
                <th>{labels.rpm}</th>
                <th>{labels.maxTorque}</th>
                <th>{labels.rpm}</th>
            </tr>
        </thead>
        <tbody>
            {runs.map(({ kind, sheet }) => (
                <tr key={kind}>
                    <td>
                        <svg className={styles.swatch} width={46} height={12}>
                            <line x1={0} x2={20} y1={6} y2={6} stroke={inks[kind]} strokeWidth={2} />
                            <line x1={26} x2={46} y1={6} y2={6} stroke={inks[kind]} strokeWidth={1.6} strokeDasharray="4 3" />
                        </svg>
                        {labels[runLabels[kind]]}
                    </td>
                    <td>{formatDate(sheet.date)}</td>
                    <td>{formatPower(sheet.wheelKw, units, labels)}</td>
                    <td>{formatNumber(sheet.powerRpm)}</td>
                    <td>{formatTorque(sheet.wheelNm, units, labels)}</td>
                    <td>{formatNumber(sheet.torqueRpm)}</td>
                </tr>
            ))}
        </tbody>
    </table>
);

export default RunTable;
