import type { Compare, Labels } from "../types";
import styles from "./Screen.module.css";

interface LegendProps {
    compare?: Compare;
    labels: Labels;
}

// Which line is which: this run, the car's last run and its first
const Legend = ({ compare, labels }: LegendProps) => (
    <div className={styles.legend}>
        <span className={`${styles.swatch} ${styles.swatchLive}`} />
        <span>{labels.thisRun}</span>
        {compare?.previous && (
            <>
                <span className={`${styles.swatch} ${styles.swatchPrevious}`} />
                <span>{labels.previous}</span>
            </>
        )}
        {compare?.first && (
            <>
                <span className={`${styles.swatch} ${styles.swatchFirst}`} />
                <span>{labels.first}</span>
            </>
        )}
    </div>
);

export default Legend;
