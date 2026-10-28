// The recent runs on the connected dyno, or every run of one car, newest first. A row opens its sheet
import { renderSheet } from "./sheet.js";
import { t, el, formatDate, powerText, torqueText } from "./page.js";

function row(sheet, onOpen) {
    return el(
        "button",
        { class: "run-row", type: "button", onClick: () => onOpen(sheet) },
        el("span", { class: "dim", text: formatDate(sheet.date) }),
        el("span", { class: "run-car", dir: "auto" }, sheet.label, " ", el("span", { class: "plate", text: sheet.plate })),
        el("span", { class: "power", text: powerText(sheet.wheelKw) }),
        el("span", { class: "torque", text: torqueText(sheet.wheelNm) }),
        el("span", { class: "dim", text: sheet.drive })
    );
}

function table(history, onOpen) {
    if (history.loading && !history.runs.length) return el("div", { class: "empty" }, el("div", { class: "spinner" }));
    if (!history.runs.length) return el("div", { class: "empty" }, el("p", { text: t("laptop:historyEmpty") }));

    return el(
        "div",
        { class: "runs" },
        el("div", { class: "run-row head" }, el("span", { text: t("laptop:date") }), el("span", { text: t("laptop:car") }), el("span", { text: t("nui:power") }), el("span", { text: t("nui:torque") }), el("span", { text: t("nui:drivetrain") })),
        history.runs.map((sheet) => row(sheet, onOpen))
    );
}

// handlers: onOpen(sheet), onBack(), onPlate(plate)
export function renderHistory(container, history, handlers) {
    const back = el("button", { class: "btn", type: "button", text: t("laptop:back"), onClick: handlers.onBack });

    if (history.selected) {
        const sheet = history.selected;
        const plateButton = !history.plate && el("button", { class: "btn", type: "button", text: t("laptop:allRuns"), onClick: () => handlers.onPlate(sheet.plate) });

        return renderSheet(container, sheet, [back, plateButton]);
    }

    const title = history.plate ? t("laptop:plateTitle", history.plate) : t("laptop:historyTitle");

    container.replaceChildren(el("div", { class: "history" }, el("div", { class: "history-top" }, history.plate && back, el("span", { class: "history-title", dir: "auto", text: title })), table(history, handlers.onOpen)));
}