// ── Jira raw API types ─────────────────────────────────────────────────────

export interface JiraBoard {
  id: number;
  name: string;
  type: "scrum" | "kanban";
  location?: { displayName: string; projectName: string };
}

export interface JiraSprint {
  id: number;
  name: string;
  state: "active" | "closed" | "future";
  startDate?: string;
  endDate?: string;
  completeDate?: string;
  goal?: string;
}

export interface JiraField {
  id: string;
  name: string;
  schema?: { type: string };
  custom: boolean;
}

export interface JiraIssue {
  id: string;
  key: string;
  fields: Record<string, unknown> & {
    summary: string;
    status: { name: string; statusCategory: { key: string } };
    created: string;
    resolutiondate?: string | null;
  };
}

// ── Processed data types ───────────────────────────────────────────────────

export interface VelocityEntry {
  sprintId: number;
  sprintName: string;
  startDate: string;
  endDate: string;
  committed: number;
  completed: number;
}

export interface BurndownPoint {
  label: string;         // e.g. "Day 3" or date string
  dateStr: string;       // ISO date
  ideal: number;
  actual: number | null; // null for future days
  projected?: number;    // linear projection for future days
  scopeAdded?: number;   // points added this day
  isWeekend: boolean;
  isFuture: boolean;
}

export interface BurndownMeta {
  sprintName: string;
  startDate: string;
  endDate: string;
  initialPoints: number;
  completedPoints: number;
  remainingPoints: number;
  projectedEndDate: string | null;
  pointsFieldName: string;
}

export interface TeamVelocity {
  boardId: string;
  boardName: string;
  avgVelocity: number;
  sprintLengthDays: number;
  lastSprints: VelocityEntry[];
}

export interface ProjectBurnPoint {
  label: string;
  totalRemaining: number | null;
  projected: number | null;
  isFuture: boolean;
  teamContributions: Record<string, number>; // boardId → points completed that sprint
}

// ── Dashboard / widget config types ───────────────────────────────────────

export type WidgetType = "velocity" | "burndown" | "project-burn-rate";
export type WidgetSize = "half" | "full";

export interface VelocityWidgetConfig {
  boardId: string;
  boardName: string;
}

export interface BurndownWidgetConfig {
  boardId: string;
  boardName: string;
  sprintId: string;   // "active" or a sprint id
  sprintName?: string;
  pointsField: string;        // Jira field id, e.g. "story_points" or "customfield_10016"
  pointsFieldName: string;    // human-readable label
}

export interface ProjectBurnRateWidgetConfig {
  projectName: string;
  totalPoints: number;
  teams: Array<{
    boardId: string;
    name: string;
  }>;
}

export type WidgetConfig =
  | { type: "velocity"; config: VelocityWidgetConfig }
  | { type: "burndown"; config: BurndownWidgetConfig }
  | { type: "project-burn-rate"; config: ProjectBurnRateWidgetConfig };

export interface Widget {
  id: string;
  type: WidgetType;
  size: WidgetSize;
  config: VelocityWidgetConfig | BurndownWidgetConfig | ProjectBurnRateWidgetConfig;
}

export interface Dashboard {
  id: string;
  name: string;
  widgets: Widget[];
  createdAt: string;
  updatedAt: string;
}

// ── App config type ────────────────────────────────────────────────────────

export interface AppConfig {
  jiraUrl: string;
  email: string;
  apiKey: string;
  createdAt: string;
  updatedAt: string;
}

export interface SafeConfig {
  jiraUrl: string;
  email: string;
  hasApiKey: boolean;
  createdAt: string;
  updatedAt: string;
}
