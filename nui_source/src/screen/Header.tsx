import styles from "./Screen.module.css";

interface HeaderProps {
    brand: string;
    title: string;
    detail?: string;
    badge?: string;
}

// The bar across the top of the screen: what it is, the car on it and its drivetrain
const Header = ({ brand, title, detail, badge }: HeaderProps) => (
    <div className={styles.header}>
        <span className={styles.brand}>
            <b>{brand}</b>
        </span>
        <span className={styles.car}>
            {title}
            {detail && <span className={styles.plate}>{detail}</span>}
        </span>
        {badge ? <span className={styles.badge}>{badge}</span> : <span />}
    </div>
);

export default Header;
