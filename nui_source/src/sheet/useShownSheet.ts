import { useEffect, useState } from "react";
import type { Sheet } from "../types";

// Milliseconds the page takes to slide in or out, matching .shown in Printout.module.css
export const slideMs = 320;

// Keeps the last sheet on the page while it slides out, and sets it down a frame after mounting so it slides in
export const useShownSheet = (sheet: Sheet | null) => {
    const [shown, setShown] = useState<Sheet | null>(sheet);
    const [visible, setVisible] = useState(false);

    useEffect(() => {
        if (sheet) {
            setShown(sheet);

            // Two frames, so the browser has drawn it out of view before the transition starts
            let frame = requestAnimationFrame(() => {
                frame = requestAnimationFrame(() => setVisible(true));
            });

            return () => cancelAnimationFrame(frame);
        }

        setVisible(false);

        const timer = window.setTimeout(() => setShown(null), slideMs);

        return () => window.clearTimeout(timer);
    }, [sheet]);

    return { shown, visible };
};
