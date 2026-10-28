import { useDyno } from "../state/useDyno";
import styles from "./Screen.module.css";
import ScreenView from "./ScreenView";

interface ScreenGridProps {
    slots: number;
    columns: number;
}

// One dyno's screen in its tile of the page, from what Lua sends that slot
const ScreenTile = ({ slot }: { slot: number }) => {
    const dyno = useDyno(slot);

    return <ScreenView {...dyno} />;
};

// The screen page as an atlas: every screen near the player is a 1280x720 tile of the one DUI, and Lua draws each
// screen's face from its own tile, so all of them show their own dyno at once
const ScreenGrid = ({ slots, columns }: ScreenGridProps) => (
    <div className={styles.grid} style={{ gridTemplateColumns: `repeat(${columns}, 1280px)` }}>
        {Array.from({ length: slots }, (_, i) => (
            <ScreenTile key={i + 1} slot={i + 1} />
        ))}
    </div>
);

export default ScreenGrid;
