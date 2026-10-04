// Mirrors the serde shapes emitted by the Rust core (src-tauri/src/*).
// EventKind uses snake_case; most structs serialize camelCase.

export type EventKind =
  | "session_started"
  | "quest_accepted"
  | "quest_completed"
  | "location_changed";

export interface ChronicleEvent {
  id: string;
  type: EventKind;
  timestamp: number;
  characterId: string;
  questId?: number | null;
  title?: string | null;
  description?: string | null;
  objectivesText?: string | null;
  zone?: string | null;
  subzone?: string | null;
  mapId?: number | null;
  level?: number | null;
}

export interface Character {
  id: string;
  name: string;
  realm: string;
  race: string;
  class: string;
  level: number;
  events: ChronicleEvent[];
}

export interface History {
  characters: Record<string, Character>;
  selectedDirectory?: string | null;
  lastImport?: number | null;
}

export interface Check {
  label: string;
  passed: boolean;
}

export interface Discovery {
  checks: Check[];
  files: string[];
}

export interface ImportResult {
  added: number;
  duplicates: number;
  dropped: number;
  conflicts: number;
}

export interface BatchResult {
  results: ImportResult[];
  errors: string[];
  importedFiles: number;
}
