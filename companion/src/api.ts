import type { BatchResult, Discovery, History } from "./types";

// True only inside the Tauri webview. In a plain browser (used for visual
// verification of the layout) the backend commands are unavailable, so the UI
// falls back to the illustrative fixture below.
export function inTauri(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<T>(cmd, args);
}

/** Native folder picker. Returns the chosen path, or null if cancelled. */
export async function chooseWowFolder(): Promise<string | null> {
  const { open } = await import("@tauri-apps/plugin-dialog");
  const picked = await open({ directory: true, multiple: false, title: "Choose your World of Warcraft folder" });
  return typeof picked === "string" ? picked : null;
}

export const discover = (path: string) => invoke<Discovery>("discover", { path });
export const importJourney = (path: string) => invoke<BatchResult>("import_journey", { path });
export const getTimeline = () => invoke<History>("timeline");
export const storySoFar = (characterId: string) =>
  invoke<string>("story_so_far", { characterId });

/** Persist the validated folder immediately, independent of a successful import.
 *  A no-op in browser preview, where the backend commands are unavailable. */
export const rememberFolder = (path: string): Promise<void> =>
  inTauri() ? invoke<void>("remember_folder", { path }) : Promise.resolve();

// Illustrative offline data for browser preview only — never shown inside Tauri.
export const FIXTURE: History = {
  selectedDirectory: null,
  lastImport: Math.floor(new Date("2026-10-02T21:51:00").getTime() / 1000),
  characters: {
    "Explorer-Fixture": {
      id: "Explorer-Fixture",
      name: "Explorer",
      realm: "Fixture realm",
      race: "Undead",
      class: "Paladin",
      level: 8,
      events: [
        {
          id: "loc1",
          type: "location_changed",
          timestamp: Math.floor(new Date("2026-10-02T21:20:00").getTime() / 1000),
          characterId: "Explorer-Fixture",
          zone: "Zephras Isle",
          subzone: "Shen'dar Village",
        },
        {
          id: "q1",
          type: "quest_accepted",
          timestamp: Math.floor(new Date("2026-10-02T21:25:00").getTime() / 1000),
          characterId: "Explorer-Fixture",
          questId: 92516,
          title: "Hippogryph Harassment",
          objectivesText: "Drive off the hippogryphs harassing the village.",
        },
        {
          id: "q1c",
          type: "quest_completed",
          timestamp: Math.floor(new Date("2026-10-02T21:51:00").getTime() / 1000),
          characterId: "Explorer-Fixture",
          questId: 92516,
          title: "Hippogryph Harassment",
          zone: "Zephras Isle",
        },
      ],
    },
  },
};
