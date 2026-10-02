import { useEffect, useMemo, useState } from "react";
import {
  chooseWowFolder,
  discover,
  FIXTURE,
  getTimeline,
  importJourney,
  inTauri,
  storySoFar,
} from "./api";
import type { Character, ChronicleEvent, History } from "./types";

const TAURI = inTauri();

function fmtTime(ts: number): string {
  return new Date(ts * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function dayKey(ts: number): string {
  return new Date(ts * 1000)
    .toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" })
    .toUpperCase();
}

function typeLabel(kind: ChronicleEvent["type"]): string {
  switch (kind) {
    case "location_changed":
      return "Location";
    case "quest_accepted":
      return "Quest accepted";
    case "quest_completed":
      return "Quest completed";
    case "session_started":
      return "Session";
  }
}

function headline(e: ChronicleEvent): string {
  switch (e.type) {
    case "location_changed":
      return e.zone ? `Arrived in ${e.zone}` : "Travelled to a new area";
    case "quest_accepted":
    case "quest_completed":
      return e.title ?? `Quest #${e.questId ?? "?"}`;
    case "session_started":
      return "Play session";
  }
}

function detail(e: ChronicleEvent): string {
  switch (e.type) {
    case "location_changed":
      return e.subzone ?? "";
    case "quest_accepted": {
      const base = `Quest #${e.questId ?? "?"}`;
      return e.objectivesText || e.description ? `${base} · Captured objectives available` : base;
    }
    case "quest_completed":
      return [e.zone, `Quest #${e.questId ?? "?"}`].filter(Boolean).join(" · ");
    case "session_started":
      return e.level ? `Level ${e.level}` : "";
  }
}

interface Day {
  key: string;
  events: ChronicleEvent[];
}

function groupByDay(events: ChronicleEvent[]): Day[] {
  const ordered = [...events].sort((a, b) => a.timestamp - b.timestamp);
  const days: Day[] = [];
  for (const e of ordered) {
    const key = dayKey(e.timestamp);
    const last = days[days.length - 1];
    if (last && last.key === key) last.events.push(e);
    else days.push({ key, events: [e] });
  }
  return days;
}

export default function App() {
  const [history, setHistory] = useState<History>(TAURI ? { characters: {} } : FIXTURE);
  const [folder, setFolder] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [status, setStatus] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [recap, setRecap] = useState<string | null>(null);

  const characters = useMemo(() => Object.values(history.characters), [history]);
  const active: Character | undefined =
    characters.find((c) => c.id === selectedId) ?? characters[0];

  const days = useMemo(() => (active ? groupByDay(active.events) : []), [active]);

  useEffect(() => {
    if (!TAURI) return;
    getTimeline()
      .then((h) => {
        setHistory(h);
        if (h.selectedDirectory) setFolder(h.selectedDirectory);
      })
      .catch((e) => setError(String(e)));
  }, []);

  useEffect(() => {
    if (!selectedId && characters.length) setSelectedId(characters[0].id);
  }, [characters, selectedId]);

  const lastImportLine = useMemo(() => {
    if (history.lastImport) {
      return `Last import: ${fmtTime(history.lastImport)} · WoW saves on /reload or logout`;
    }
    return "No journey imported yet · choose your WoW folder, then import";
  }, [history.lastImport]);

  async function onChooseFolder() {
    setError(null);
    try {
      const picked = await chooseWowFolder();
      if (!picked) return;
      setFolder(picked);
      const report = await discover(picked);
      const ok = report.files.length > 0;
      if (ok) {
        setStatus(`Found ${report.files.length} saved journey file(s). Ready to import.`);
      } else {
        const checks = report.checks
          .map((c) => `${c.label} ${c.passed ? "✓" : "✗"}`)
          .join(" · ");
        setStatus(`No AzerothChronicle.lua found. Enable the addon and /reload or log out of WoW. ${checks}`);
      }
    } catch (e) {
      setError(String(e));
    }
  }

  async function onImport() {
    if (!folder) {
      setError("Choose your WoW folder first.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const report = await importJourney(folder);
      const added = report.results.reduce((n, r) => n + r.added, 0);
      const dups = report.results.reduce((n, r) => n + r.duplicates, 0);
      const next = await getTimeline();
      setHistory(next);
      setStatus(
        `Imported ${report.importedFiles} file(s) · ${added} new event(s), ${dups} already recorded` +
          (report.errors.length ? ` · ${report.errors.length} file(s) skipped` : ""),
      );
      if (report.errors.length) setError(report.errors.join("\n"));
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  async function onRecap() {
    if (!active) return;
    setBusy(true);
    setError(null);
    try {
      if (TAURI) {
        setRecap(await storySoFar(active.id));
      } else {
        setRecap(
          "You arrived in Zephras Isle, accepted Hippogryph Harassment, and later completed it.",
        );
      }
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="app">
      <header className="top">
        <div>
          <div className="eyebrow">Azeroth Chronicle</div>
          <h2>{active ? `${active.name}'s journey` : "Explorer's journey"}</h2>
          <div className="muted">
            {active
              ? `Level ${active.level} · ${active.race} ${active.class} · ${active.realm}`
              : "Import a saved journey to begin"}
          </div>
        </div>
        <div className="actions">
          {characters.length > 1 && (
            <select
              className="char-select"
              value={active?.id}
              onChange={(ev) => setSelectedId(ev.target.value)}
            >
              {characters.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name} · {c.realm}
                </option>
              ))}
            </select>
          )}
          <button onClick={onChooseFolder} disabled={busy}>
            Choose WoW folder
          </button>
          <button className="primary" onClick={onImport} disabled={busy}>
            Import saved journey
          </button>
        </div>
      </header>

      <div className="status">{status || lastImportLine}</div>
      {error && <div className="error" role="alert">{error}</div>}

      <div className="layout">
        <main className="journal">
          {days.length === 0 && (
            <div className="empty">
              <p>No events yet.</p>
              <p className="muted">
                Choose your World of Warcraft folder and import your saved journey. Your
                SavedVariables file is read only — Azeroth Chronicle never writes to or runs
                anything in your game folder.
              </p>
            </div>
          )}
          {days.map((day) => (
            <section key={day.key}>
              <div className="date">{day.key}</div>
              {day.events.map((e) => (
                <div className="event" key={e.id}>
                  <time>{fmtTime(e.timestamp)}</time>
                  <div>
                    <div className="type">{typeLabel(e.type)}</div>
                    <h3>{headline(e)}</h3>
                    {detail(e) && <p>{detail(e)}</p>}
                  </div>
                </div>
              ))}
            </section>
          ))}
        </main>

        <aside className="recap">
          <div className="eyebrow">Your recorded adventure</div>
          <h2 className="recap-title">Story So Far</h2>
          <p>
            {recap ??
              "Generate a recap grounded only in the events you have captured. Nothing is invented."}
          </p>
          <p className="muted">
            Offline recap · captured events only. Missing historical quest text is not filled in.
          </p>
          <button className="primary" onClick={onRecap} disabled={busy || !active}>
            Generate offline recap
          </button>
          <p className="muted">
            Bedrock Nova is optional. Sending events to AWS requires confirmation and may incur
            charges.
          </p>
        </aside>
      </div>
    </div>
  );
}
