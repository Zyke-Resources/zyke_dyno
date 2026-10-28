import DynoGraph from "../graph/DynoGraph";
import { formatNumber } from "../graph/live";
import { toPower, toTorque } from "../graph/units";
import type { Labels, Sheet, Units } from "../types";
import Header from "./Header";
import Legend from "./Legend";
import Readout from "./Readout";
import styles from "./Screen.module.css";

interface StandbyProps {
    last: Sheet | null;
    labels: Labels;
    units: Units;
}

// The screen between runs: the last result with its graph, or how to start when there is none yet
const Standby = ({ last, labels, units }: StandbyProps) => {
    if (!last) {
        return (
            <div className={styles.screen}>
                <Header brand={labels.dyno ?? "Dyno"} title={labels.standby ?? ""} />
                <div className={styles.standby}>
                    <span className={styles.standbyTitle}>{labels.standby}</span>
                    <span className={styles.standbyHint}>{labels.standbyHint}</span>
                </div>
            </div>
        );
    }

    const at = (rpm: number) => `${labels.at} ${formatNumber(rpm)} ${labels.rpm}`;

    return (
        <div className={styles.screen}>
            <Header brand={labels.dyno ?? "Dyno"} title={last.label} detail={last.plate} badge={last.drive} />
            <div className={styles.body}>
                <DynoGraph curve={last.curve} compare={last.compare} units={units} labels={labels} width={900} height={590} />
                <div className={styles.side}>
                    <span className={styles.sideTitle}>{labels.lastRun}</span>
                    <Readout label={labels.peakPower} value={formatNumber(toPower(last.wheelKw, units.power))} unit={labels[units.power]} tone="power" />
                    <span className={styles.note}>{at(last.powerRpm)}</span>
                    <Readout label={labels.peakTorque} value={formatNumber(toTorque(last.wheelNm, units.torque))} unit={labels[units.torque]} tone="torque" />
                    <span className={styles.note}>{at(last.torqueRpm)}</span>
                    <Readout size="small" label={labels.engine} value={formatNumber(toPower(last.engineKw, units.power))} unit={labels[units.power]} />
                    <Legend compare={last.compare} labels={labels} />
                </div>
            </div>
        </div>
    );
};

export default Standby;
