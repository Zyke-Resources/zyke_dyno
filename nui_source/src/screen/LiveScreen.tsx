import DynoGraph from "../graph/DynoGraph";
import { formatNumber, getLiveValues } from "../graph/live";
import { toPower, toTorque } from "../graph/units";
import type { Labels, ProgressPayload, RunPayload, Units } from "../types";
import Header from "./Header";
import Legend from "./Legend";
import Readout from "./Readout";
import styles from "./Screen.module.css";

interface LiveScreenProps {
    run: RunPayload;
    progress: ProgressPayload | null;
    labels: Labels;
    units: Units;
}

// The screen while a run is on: the graph drawing itself as the driver pulls, with the revs, the power and torque
// the engine makes this moment, the peaks so far, the speed at the rollers and the gear beside it
const LiveScreen = ({ run, progress, labels, units }: LiveScreenProps) => {
    const revealed = progress?.revealed ?? 0;
    const live = getLiveValues(run.curve, Math.max(revealed, 1));
    const drawing = revealed >= 1;
    const power = progress ? formatNumber(toPower(progress.power, units.power)) : "-";
    const torque = progress ? formatNumber(toTorque(progress.torque, units.torque)) : "-";

    return (
        <div className={styles.screen}>
            <Header brand={labels.dyno ?? "Dyno"} title={run.label} detail={run.plate} badge={run.drive} />
            <div className={styles.body}>
                <DynoGraph curve={run.curve} compare={run.compare} units={units} labels={labels} revealed={revealed} width={900} height={590} />
                <div className={styles.side}>
                    <Readout label={labels.rpm} value={formatNumber(progress?.rpm ?? 0)} unit="" />
                    <Readout label={labels.power} value={power} unit={labels[units.power]} tone="power" />
                    <Readout label={labels.torque} value={torque} unit={labels[units.torque]} tone="torque" />
                    <div className={styles.peaks}>
                        <Readout size="small" label={labels.peakPower} value={drawing ? formatNumber(toPower(live.peakPower, units.power)) : "-"} unit={labels[units.power]} tone="power" />
                        <Readout size="small" label={labels.peakTorque} value={drawing ? formatNumber(toTorque(live.peakTorque, units.torque)) : "-"} unit={labels[units.torque]} tone="torque" />
                        <Readout size="small" label={labels.speed} value={formatNumber(progress?.speed ?? 0)} unit={labels[units.speed]} />
                        <Readout size="small" label={labels.gear} value={String(progress?.gear ?? "-")} unit="" />
                    </div>
                    <Legend compare={run.compare} labels={labels} />
                </div>
            </div>
        </div>
    );
};

export default LiveScreen;
