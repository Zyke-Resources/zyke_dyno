import { useEffect, useState } from "react";
import { formatNumber } from "../graph/live";
import type { Labels, Sheet, Units } from "../types";
import PrintGraph from "./PrintGraph";
import PrintHeader from "./PrintHeader";
import RunTable from "./RunTable";
import { fill, getRuns } from "./print";
import styles from "./Printout.module.css";
import { useShownSheet } from "./useShownSheet";

interface PrintoutProps {
    sheet: Sheet | null;
    labels: Labels;
    units: Units;
}

// A landscape A4 page at 96 dpi, scaled to fit the player's screen above the key panel
const pageWidth = 1123;
const pageHeight = 794;

const getScale = () => Math.min((window.innerWidth * 0.86) / pageWidth, (window.innerHeight * 0.8) / pageHeight);

// The result as the dyno's printer puts it on paper: what was run, its peaks, the graph over the car's last and
// first runs and the run list under it. It slides up into view when shown and drops away when closed
const Printout = ({ sheet: current, labels, units }: PrintoutProps) => {
    const [scale, setScale] = useState(getScale);
    const { shown: sheet, visible } = useShownSheet(current);

    useEffect(() => {
        const onResize = () => setScale(getScale());

        window.addEventListener("resize", onResize);

        return () => window.removeEventListener("resize", onResize);
    }, []);

    if (!sheet) return null;

    const runs = getRuns(sheet);
    const loss = `${formatNumber((sheet.loss ?? 0) * 100)}%`;

    return (
        <div className={styles.wrapper}>
            <div className={`${styles.slide} ${visible ? styles.shown : ""}`}>
                <div className={styles.page} style={{ width: pageWidth, height: pageHeight, transform: `translateY(-4vh) rotate(-0.6deg) scale(${scale})` }}>
                    <PrintHeader sheet={sheet} units={units} labels={labels} />
                    <PrintGraph runs={runs} units={units} labels={labels} width={pageWidth - 96} height={400} />
                    <RunTable runs={runs} units={units} labels={labels} />
                    <footer className={styles.footer}>
                        <span>{fill(labels.footnote, loss)}</span>
                        <span>1 / 1</span>
                    </footer>
                </div>
            </div>
        </div>
    );
};

export default Printout;
