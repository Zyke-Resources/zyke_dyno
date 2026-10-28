// Shared by the app's views: the words and units from client/laptop.lua, posting, number and date formats, and a
// small DOM builder
const setup = { strings: {}, units: { power: "hp", torque: "nm", speed: "kmh" } };

const kwPerUnit = { hp: 0.7457, ps: 0.735499, kw: 1 };
const nmPerUnit = { nm: 1, lbft: 1.355818 };

// Outside the game the page answers its own posts from dev/mock.js, which stays out of git
export async function start() {
    if (!window.Laptop) await import("./dev/mock.js").then((mock) => mock.loadSdk());
    if (!window.Laptop.inGame) await import("./dev/mock.js").then((mock) => mock.install());

    const [, data] = await Promise.all([window.Laptop.ready(), window.Laptop.post("dyno:Setup").catch(() => null)]);

    Object.assign(setup, data || {});
    document.title = t("laptop:appName");
    document.querySelectorAll("[data-t]").forEach((node) => (node.textContent = t(node.dataset.t)));
    document.querySelectorAll("[data-t-label]").forEach((node) => {
        node.setAttribute("aria-label", t(node.dataset.tLabel));
        node.title = t(node.dataset.tLabel);
    });
}

// A locale string with each %s filled in order, or the key itself when it is missing
export function t(key, ...args) {
    const text = setup.strings[key];
    if (typeof text !== "string") return key;

    let index = 0;

    return text.replace(/%%|%s/g, (token) => (token === "%%" ? "%" : String(args[index++] ?? "")));
}

// Every reply is {ok, error?, ...}; a failed post becomes the same shape
export async function call(endpoint, data) {
    try {
        const result = await window.Laptop.post(`dyno:${endpoint}`, data);

        return result && typeof result === "object" ? result : { ok: false, error: "laptop:error:unavailable" };
    } catch (error) {
        console.error(error);

        return { ok: false, error: "laptop:error:unavailable" };
    }
}

export const units = () => setup.units;
export const toPower = (kw) => kw / kwPerUnit[setup.units.power];
export const toTorque = (nm) => nm / nmPerUnit[setup.units.torque];
export const toSpeed = (metres) => (setup.units.speed === "mph" ? metres * 2.236936 : metres * 3.6);
export const whole = (value) => Number(value || 0).toFixed(0);
export const powerText = (kw) => `${whole(toPower(kw))} ${t(`unit:${setup.units.power}`)}`;
export const torqueText = (nm) => `${whole(toTorque(nm))} ${t(`unit:${setup.units.torque}`)}`;
export const speedText = (metres) => `${whole(toSpeed(metres))} ${t(`unit:${setup.units.speed}`)}`;
export const atRpm = (rpm) => `${t("nui:at")} ${whole(rpm)} ${t("nui:rpm")}`;

// A dyno's name, "Dyno 1" and so on when its server gave it none
// A dyno's own name, and the name the player sees: the one they gave it when they renamed it
export const ownName = (dyno) => dyno.label || t("laptop:dynoNumber", dyno.id);
export const dynoName = (dyno) => dyno.name || ownName(dyno);

// Seconds since the epoch, in the laptop's 12 or 24 hour clock
export function formatDate(seconds) {
    const options = { dateStyle: "medium", timeStyle: "short" };
    const clock24h = window.Laptop.context?.settings?.clock24h;

    if (clock24h !== undefined) options.hourCycle = clock24h ? "h23" : "h12";

    try {
        return new Intl.DateTimeFormat(window.Laptop.context?.settings?.language, options).format(new Date(seconds * 1000));
    } catch (error) {
        return new Intl.DateTimeFormat(undefined, options).format(new Date(seconds * 1000));
    }
}

// el("p", {class: "note", text: "Hi"}, child, ...); strings become text nodes, never HTML
export function el(tag, props = {}, ...children) {
    const node = document.createElement(tag);

    for (const [key, value] of Object.entries(props)) {
        if (value === null || value === undefined || value === false) continue;

        if (key === "class") node.className = value;
        else if (key === "text") node.textContent = value;
        else if (key.startsWith("on")) node.addEventListener(key.slice(2).toLowerCase(), value);
        else node.setAttribute(key, value === true ? "" : value);
    }

    node.append(...children.flat(Infinity).filter((child) => child !== null && child !== undefined && child !== false));

    return node;
}