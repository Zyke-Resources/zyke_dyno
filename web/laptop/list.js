// The dynos the player's job may use, each with what it is doing and its last result, to connect to one. The ones
// they connected to before stand first, under their own heading, and can be forgotten
import { t, el, dynoName, ownName, powerText, torqueText } from "./page.js";

function status(dyno) {
    if (dyno.run) return el("span", { class: "chip running" }, t("laptop:running"), el("span", { class: "plate", text: dyno.run.plate }));

    return el("span", { class: "chip free", text: t("laptop:free") });
}

function lastLine(dyno) {
    if (!dyno.last) return el("span", { class: "dim", text: t("laptop:noResult") });

    const last = dyno.last;

    return el("span", { dir: "auto" }, `${t("nui:lastRun")}: ${last.label} `, el("span", { class: "plate", text: last.plate }), ` · ${powerText(last.wheelKw)} · ${torqueText(last.wheelNm)}`);
}

function card(dyno, actions) {
    return el(
        "div",
        { class: `dyno-card ${dyno.inRange ? "" : "unreachable"}` },
        el("div", { class: "dyno-card-top" }, el("div", { class: "dyno-card-title" }, el("span", { class: "dyno-name", dir: "auto", text: dynoName(dyno) }), dyno.name ? el("span", { class: "dim own-name", dir: "auto", text: ownName(dyno) }) : ""), status(dyno)),
        el("div", { class: "dyno-card-line" }, dyno.run ? el("span", { dir: "auto", text: dyno.run.label }) : lastLine(dyno)),
        el(
            "div",
            { class: "dyno-card-bottom" },
            el("span", { class: "dim", text: dyno.inRange ? t("laptop:metresAway", dyno.distance) : `${t("laptop:outOfRange")} · ${t("laptop:metresAway", dyno.distance)}` }),
            el(
                "div",
                { class: "dyno-card-actions" },
                dyno.saved ? el("button", { class: "btn", type: "button", text: t("laptop:forget"), onClick: () => actions.onForget(dyno.id) }) : "",
                el("button", { class: "btn primary", type: "button", disabled: !dyno.inRange, text: t("laptop:connect"), onClick: () => actions.onConnect(dyno.id) })
            )
        )
    );
}

function section(title, dynos, actions) {
    return el("section", { class: "dyno-section" }, title ? el("h2", { class: "dyno-section-title", text: title }) : "", el("div", { class: "dyno-grid" }, dynos.map((dyno) => card(dyno, actions))));
}

export function renderList(container, state, actions) {
    if (state.loading && !state.dynos.length) return container.replaceChildren(el("div", { class: "empty" }, el("div", { class: "spinner" })));
    if (!state.dynos.length) return container.replaceChildren(el("div", { class: "empty" }, el("p", { text: t("laptop:noDynos") })));

    const saved = state.dynos.filter((dyno) => dyno.saved);
    const others = state.dynos.filter((dyno) => !dyno.saved);

    if (!saved.length) return container.replaceChildren(section(null, others, actions));

    container.replaceChildren(section(t("laptop:saved"), saved, actions), others.length ? section(t("laptop:otherDynos"), others, actions) : "");
}