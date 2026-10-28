import type { useDyno } from "../state/useDyno";
import LiveScreen from "./LiveScreen";
import Standby from "./Standby";

type ScreenViewProps = Pick<ReturnType<typeof useDyno>, "labels" | "units" | "run" | "progress" | "last">;

// What the screen beside the dyno shows: the run while one is on, else the last result
const ScreenView = ({ labels, units, run, progress, last }: ScreenViewProps) =>
    run ? <LiveScreen run={run} progress={progress} labels={labels} units={units} /> : <Standby last={last} labels={labels} units={units} />;

export default ScreenView;
