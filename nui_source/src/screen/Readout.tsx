import styles from "./Screen.module.css";

interface ReadoutProps {
    label: string;
    value: string;
    unit: string;
    tone?: "power" | "torque";
    size?: "large" | "small";
}

// One number on the screen with what it is and its unit, such as POWER 312 HP
const Readout = ({ label, value, unit, tone, size = "large" }: ReadoutProps) => (
    <div className={`${styles.readout} ${size === "small" ? styles.small : ""}`}>
        <span className={styles.readoutLabel}>{label}</span>
        <span className={`${styles.readoutValue} ${tone ? styles[tone] : ""}`}>
            {value}
            <span className={styles.readoutUnit}>{unit}</span>
        </span>
    </div>
);

export default Readout;
