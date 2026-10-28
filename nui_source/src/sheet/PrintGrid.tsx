import type { Frame } from "../graph/paths";
import { toX } from "../graph/paths";
import styles from "./Printout.module.css";

interface PrintGridProps {
    frame: Frame;
    powerLabel: string;
    torqueLabel: string;
    rpmLabel: string;
}

// Major rows carry the numbers, and a minor row runs between each two
const rows = 5;
const minorRpm = 250;

// The printed grid: fine lines every 250 rpm and half row, heavier ones on the numbered values
const PrintGrid = ({ frame, powerLabel, torqueLabel, rpmLabel }: PrintGridProps) => {
    const yOf = (share: number) => frame.height - frame.height * share;
    const minorRows = Array.from({ length: rows * 2 + 1 }, (_, index) => index);
    const rpms: number[] = [];

    for (let rpm = Math.ceil(frame.minRpm / minorRpm) * minorRpm; rpm <= frame.maxRpm; rpm += minorRpm) rpms.push(rpm);

    return (
        <g>
            {minorRows.map((row) => {
                const major = row % 2 === 0;
                const y = yOf(row / (rows * 2));

                return (
                    <g key={`row-${row}`}>
                        <line className={major ? styles.gridMajor : styles.gridMinor} x1={0} x2={frame.width} y1={y} y2={y} />
                        {major && (
                            <>
                                <text className={styles.tick} x={-8} y={y + 4} textAnchor="end">{Math.round((frame.maxPower * row) / (rows * 2))}</text>
                                <text className={styles.tick} x={frame.width + 8} y={y + 4} textAnchor="start">{Math.round((frame.maxTorque * row) / (rows * 2))}</text>
                            </>
                        )}
                    </g>
                );
            })}

            {rpms.map((rpm) => {
                const major = rpm % 1000 === 0;
                const x = toX(frame, rpm);

                return (
                    <g key={`rpm-${rpm}`}>
                        <line className={major ? styles.gridMajor : styles.gridMinor} x1={x} x2={x} y1={0} y2={frame.height} />
                        {major && <text className={styles.tick} x={x} y={frame.height + 16} textAnchor="middle">{rpm / 1000}</text>}
                    </g>
                );
            })}

            <rect className={styles.plotBorder} x={0} y={0} width={frame.width} height={frame.height} />
            <text className={styles.axisTitle} transform={`translate(-38, ${frame.height / 2}) rotate(-90)`} textAnchor="middle">{powerLabel}</text>
            <text className={styles.axisTitle} transform={`translate(${frame.width + 40}, ${frame.height / 2}) rotate(90)`} textAnchor="middle">{torqueLabel}</text>
            <text className={styles.axisTitle} x={frame.width / 2} y={frame.height + 36} textAnchor="middle">{rpmLabel}</text>
        </g>
    );
};

export default PrintGrid;
