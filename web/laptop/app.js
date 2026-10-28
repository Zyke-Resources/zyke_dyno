// The Dyno app: pick a dyno, connect to it, then follow its live run, read its last result and its history. It
// opens on the dyno it was last connected to, and lists the ones connected to before first. The server checks every
// request, and client/laptop.lua sends the live run here while the page is connected
import { start, call, t, el, dynoName, ownName } from "./page.js";
import { renderList } from "./list.js";
import { renderLive } from "./live.js";
import { renderSheet } from "./sheet.js";
import { renderHistory } from "./history.js";

// Milliseconds between refreshes of the list, and of the connected dyno's status, which also tells the client the
// page is still open
const listMs = 5000;
const statusMs = 4000;
// Milliseconds after a run ends before its result is asked for, so the server has saved it
const resultDelayMs = 1500;

const titleNode = document.getElementById("title");
const statusNode = document.getElementById("status");
const tabsNode = document.getElementById("tabs");
const contentNode = document.getElementById("content");
const errorNode = document.getElementById("error");
const disconnectNode = document.getElementById("disconnect");
const refreshNode = document.getElementById("refresh");

const emptyHistory = () => ({ runs: [], loading: false, plate: null, selected: null });
const state = { view: "list", tab: "live", dynos: [], loading: true, error: null, dyno: null, last: null, live: null, history: emptyHistory(), renaming: false };
let timer = null;

function showError(error) {
    state.error = error;
    errorNode.hidden = !error;

    if (error) errorNode.replaceChildren(el("span", { text: t(error) }), el("button", { class: "btn", type: "button", text: t("laptop:retry"), onClick: retry }));
}

// The connected dyno's name with a button to rename it, which only this character sees. Left alone while the name is
// being typed, as the status refreshes the header every few seconds
function drawTitle(connected) {
    if (state.renaming) return;
    if (!connected) return titleNode.replaceChildren(el("span", { class: "title", text: t("laptop:pickDyno") }));

    titleNode.replaceChildren(
        el("span", { class: "title", dir: "auto", title: state.dyno.name ? ownName(state.dyno) : null, text: dynoName(state.dyno) }),
        el("button", { class: "icon-btn rename", type: "button", title: t("laptop:rename"), "aria-label": t("laptop:rename"), onClick: startRename })
    );
}

function startRename() {
    const input = el("input", { class: "rename-input", type: "text", maxlength: "32", dir: "auto", placeholder: ownName(state.dyno) });
    let done = false;

    const finish = (save) => {
        if (done) return;

        done = true;
        state.renaming = false;

        if (save) return rename(input.value);

        drawHeader();
    };

    input.value = state.dyno.name || "";
    input.addEventListener("keydown", (event) => {
        if (event.key !== "Enter" && event.key !== "Escape") return;

        event.preventDefault();
        event.stopPropagation();
        finish(event.key === "Enter");
    });
    input.addEventListener("blur", () => finish(true));

    state.renaming = true;
    titleNode.replaceChildren(input, el("span", { class: "dim rename-hint", text: t("laptop:renameHint") }));
    input.focus();
    input.select();
}

// An empty name gives the dyno its own name back
async function rename(name) {
    if (name.trim() === (state.dyno?.name || "")) return drawHeader();

    const result = await call("Rename", { name });

    if (state.view !== "dyno") return;
    if (result.ok) state.dyno = result.dyno;

    showError(result.ok ? null : result.error);
    drawHeader();
}

function drawHeader() {
    const connected = state.view === "dyno" && state.dyno;

    drawTitle(connected);
    statusNode.replaceChildren(connected ? el("span", { class: `chip ${state.dyno.run ? "running" : "free"}`, text: t(state.dyno.run ? "laptop:running" : "laptop:free") }) : "");
    disconnectNode.hidden = !connected;
    tabsNode.hidden = !connected;
    tabsNode.querySelectorAll("[data-tab]").forEach((button) => button.setAttribute("aria-selected", String(button.dataset.tab === state.tab)));
}

function draw() {
    drawHeader();

    if (state.view === "list") return renderList(contentNode, state, { onConnect: connect, onForget: forget });
    if (state.tab === "live") return renderLive(contentNode, state.live);

    if (state.tab === "result") {
        if (!state.last) return contentNode.replaceChildren(el("div", { class: "empty" }, el("p", { text: t("laptop:noSheet") })));

        return renderSheet(contentNode, state.last);
    }

    renderHistory(contentNode, state.history, { onOpen: openSheet, onBack: historyBack, onPlate: loadPlate });
}

function schedule(callback, ms) {
    clearTimeout(timer);
    timer = setTimeout(callback, ms);
}

async function loadDynos() {
    const result = await call("GetDynos");

    if (state.view !== "list") return;

    state.loading = false;
    showError(result.ok ? null : result.error);

    if (result.ok) state.dynos = result.dynos || [];

    draw();
    schedule(loadDynos, listMs);
}

function showList(error) {
    Object.assign(state, { view: "list", dyno: null, last: null, live: null, history: emptyHistory(), loading: true, renaming: false });
    showError(error || null);
    draw();
    loadDynos();
}

function enter(result) {
    Object.assign(state, { view: "dyno", tab: "live", dyno: result.dyno, last: result.last || null, live: null, history: emptyHistory() });
    showError(null);
    draw();
    schedule(loadStatus, statusMs);
}

async function connect(dynoId) {
    const result = await call("Connect", { dynoId });

    if (!result.ok) return showError(result.error);

    enter(result);
}

// The dyno the player was connected to when the app last closed, or the list when there is none or it can't be
// reached any more
async function resume() {
    const result = await call("Resume");

    if (!result.ok) return showList(result.error);

    enter(result);
}

async function forget(dynoId) {
    const result = await call("Forget", { dynoId });

    showError(result.ok ? null : result.error);
    loadDynos();
}

async function loadStatus() {
    const result = await call("GetStatus");

    if (state.view !== "dyno") return;
    if (!result.ok) return showList(result.error);

    state.dyno = result.dyno;
    state.last = result.last || null;

    if (state.live && state.live.ended && state.live.ended !== "stopped") state.live.ended = state.last?.runId && state.last.runId !== state.live.runId ? "stopped" : "done";

    if (state.tab === "live") drawHeader();
    else if (state.tab === "result") draw();

    schedule(loadStatus, statusMs);
}

async function disconnect() {
    clearTimeout(timer);
    await call("Disconnect");
    showList();
}

async function loadHistory() {
    state.history = { ...emptyHistory(), loading: true };
    draw();

    const result = await call("GetHistory");

    if (!result.ok) return showList(result.error);

    state.history = { ...emptyHistory(), runs: result.runs || [] };
    draw();
}

async function loadPlate(plate) {
    state.history = { ...emptyHistory(), plate, loading: true };
    draw();

    const result = await call("GetPlateHistory", { plate });

    if (!result.ok) return showError(result.error);

    state.history = { ...emptyHistory(), plate: result.plate, runs: result.runs || [] };
    draw();
}

function openSheet(sheet) {
    state.history.selected = sheet;
    draw();
}

function historyBack() {
    if (state.history.selected) {
        state.history.selected = null;

        return draw();
    }

    loadHistory();
}

function retry() {
    if (state.view === "list") return showList();

    showError(null);
    loadStatus();
}

// A new run starts over; the same run's later messages only bring the points recorded since
function onLive(live) {
    if (state.view !== "dyno") return;

    if (!state.live || state.live.runId !== live.runId || live.from === 1) state.live = { ...live };
    else state.live = { ...state.live, ...live, compare: state.live.compare, points: state.live.points.concat(live.points) };

    if (state.dyno && !state.dyno.run) state.dyno.run = { plate: live.plate, label: live.label };
    if (state.tab === "live") draw();
}

function onLiveEnd(data) {
    if (!state.live || state.live.runId !== data.runId) return;

    state.live.ended = "done";

    if (state.dyno) state.dyno.run = null;
    if (state.tab === "live") draw();

    schedule(loadStatus, resultDelayMs);
}

await start();

window.Laptop.on("message", (message) => {
    if (message?.event === "Live") onLive(message.data);
    if (message?.event === "LiveEnd") onLiveEnd(message.data);
});

tabsNode.querySelectorAll("[data-tab]").forEach((button) =>
    button.addEventListener("click", () => {
        state.tab = button.dataset.tab;
        state.history.selected = null;

        if (state.tab === "history") return loadHistory();

        draw();
    })
);

disconnectNode.addEventListener("click", disconnect);
refreshNode.addEventListener("click", () => (state.view === "list" ? loadDynos() : state.tab === "history" ? loadHistory() : loadStatus()));
new ResizeObserver(() => state.view === "dyno" && (state.tab !== "history" || state.history.selected) && draw()).observe(contentNode);
document.body.classList.add("ready");

resume();