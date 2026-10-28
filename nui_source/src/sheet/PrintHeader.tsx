import { formatNumber } from "../graph/live";
import { toSpeed } from "../graph/units";
import type { Labels, Sheet, Units } from "../types";
import { formatDate, formatPower, formatTorque } from "./print";
import styles from "./Printout.module.css";

interface PrintHeaderProps {
    sheet: Sheet;
    units: Units;
    labels: Labels;
}

// The top of the page: what was run and when, then the peaks in a printed table
const PrintHeader = ({ sheet, units, labels }: PrintHeaderProps) => {
    const at = (rpm: number) => `@ ${formatNumber(rpm)} ${labels.rpm}`;
    const gain = sheet.gain ? `${sheet.gain.wheelKw >= 0 ? "+" : "-"}${formatPower(Math.abs(sheet.gain.wheelKw), units, labels)}` : labels.noGain;
    const details: [string | undefined, string][] = [
        [labels.vehicle, sheet.label],
        [labels.plate, sheet.plate],
        [labels.drivetrain, sheet.drive],
        [labels.gear, sheet.gear !== undefined ? String(sheet.gear) : "-"],
        [labels.redlineSpeed, sheet.redlineSpeed ? `${formatNumber(toSpeed(sheet.redlineSpeed, units.speed))} ${labels[units.speed] ?? ""}` : "-"],
    ];

    return (
        <header>
            <div className={styles.titleRow}>
                <div>
                    <div className={styles.title}>{labels.printTitle}</div>
                    <div className={styles.subtitle}>{labels.sheetTitle}</div>
                </div>
                <div className={styles.stamp}>{formatDate(sheet.date)}</div>
            </div>

            <div className={styles.details}>
                {details.map(([label, value]) => (
                    <div key={label} className={styles.detail}>
                        <span className={styles.detailLabel}>{label}</span>
                        <span className={styles.detailValue}>{value}</span>
                    </div>
                ))}
            </div>

            <table className={styles.peaks}>
                <thead>
                    <tr>
                        <th>{`${labels.maxPower} · ${labels.wheel}`}</th>
                        <th>{`${labels.maxTorque} · ${labels.wheel}`}</th>
                        <th>{labels.engine}</th>
                        <th>{labels.gain}</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td><b>{formatPower(sheet.wheelKw, units, labels)}</b> {at(sheet.powerRpm)}</td>
                        <td><b>{formatTorque(sheet.wheelNm, units, labels)}</b> {at(sheet.torqueRpm)}</td>
                        <td><b>{formatPower(sheet.engineKw, units, labels)}</b></td>
                        <td><b>{gain}</b></td>
                    </tr>
                </tbody>
            </table>
        </header>
    );
};

export default PrintHeader;
