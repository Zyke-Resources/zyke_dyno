import type { Frame } from "./paths";
import { toX } from "./paths";
import styles from "./DynoGraph.module.css";

interface AxesProps {
    frame: Frame;
    powerLabel: string;
    torqueLabel: string;
    rpmLabel: string;
}

const steps = 5;

// The grid behind the curves: rpm along the bottom in thousands, power up the left and torque up the right
const Axes = ({ frame, powerLabel, torqueLabel, rpmLabel }: AxesProps) => {
    const rows = Array.from({ length: steps + 1 }, (_, index) => index);
    const columns: number[] = [];

    for (let rpm = Math.ceil(frame.minRpm / 1000) * 1000; rpm <= frame.maxRpm; rpm += 1000) columns.push(rpm);

    return (
        <g>
            {rows.map((row) => {
                const y = frame.height - (frame.height * row) / steps;

                return (
                    <g key={`row-${row}`}>
                        <line className={styles.grid} x1={0} x2={frame.width} y1={y} y2={y} />
                        <text className={`${styles.tick} ${styles.power}`} x={-10} y={y + 5} textAnchor="end">
                            {Math.round((frame.maxPower * row) / steps)}
                        </text>
                        <text className={`${styles.tick} ${styles.torque}`} x={frame.width + 10} y={y + 5} textAnchor="start">
                            {Math.round((frame.maxTorque * row) / steps)}
                        </text>
                    </g>
                );
            })}

            {columns.map((rpm) => (
                <g key={`column-${rpm}`}>
                    <line className={styles.grid} x1={toX(frame, rpm)} x2={toX(frame, rpm)} y1={0} y2={frame.height} />
                    <text className={styles.tick} x={toX(frame, rpm)} y={frame.height + 24} textAnchor="middle">
                        {rpm / 1000}
                    </text>
                </g>
            ))}

            <text className={`${styles.axis} ${styles.power}`} x={-10} y={-16} textAnchor="end">{powerLabel}</text>
            <text className={`${styles.axis} ${styles.torque}`} x={frame.width + 10} y={-16} textAnchor="start">{torqueLabel}</text>
            <text className={styles.axis} x={frame.width} y={frame.height + 48} textAnchor="end">{`${rpmLabel} x1000`}</text>
        </g>
    );
};

export default Axes;
