import type {
  JiraBoard,
  JiraSprint,
  JiraField,
  JiraIssue,
  VelocityEntry,
  BurndownPoint,
  BurndownMeta,
} from "@/types";

export class JiraClient {
  private base: string;
  private auth: string;

  constructor(jiraUrl: string, email: string, apiKey: string) {
    this.base = jiraUrl.replace(/\/+$/, "");
    this.auth = Buffer.from(`${email}:${apiKey}`).toString("base64");
  }

  private async get<T>(path: string): Promise<T> {
    const res = await fetch(`${this.base}${path}`, {
      headers: {
        Authorization: `Basic ${this.auth}`,
        Accept: "application/json",
      },
      cache: "no-store",
    });
    if (!res.ok) {
      const text = await res.text().catch(() => res.statusText);
      throw new Error(`Jira ${res.status}: ${text}`);
    }
    return res.json() as Promise<T>;
  }

  async testConnection(): Promise<{ accountId: string; displayName: string }> {
    return this.get("/rest/api/3/myself");
  }

  // ── Boards ─────────────────────────────────────────────────────────────

  async getBoards(): Promise<JiraBoard[]> {
    const all: JiraBoard[] = [];
    let start = 0;
    const limit = 50;
    while (true) {
      const page = await this.get<{ values: JiraBoard[]; isLast: boolean }>(
        `/rest/agile/1.0/board?maxResults=${limit}&startAt=${start}`
      );
      all.push(...page.values);
      if (page.isLast || page.values.length < limit) break;
      start += limit;
    }
    return all;
  }

  // ── Sprints ─────────────────────────────────────────────────────────────

  async getSprints(boardId: number, state?: "active" | "closed" | "future"): Promise<JiraSprint[]> {
    const all: JiraSprint[] = [];
    let start = 0;
    const limit = 50;
    const stateParam = state ? `&state=${state}` : "";
    while (true) {
      const page = await this.get<{ values: JiraSprint[]; isLast: boolean }>(
        `/rest/agile/1.0/board/${boardId}/sprint?maxResults=${limit}&startAt=${start}${stateParam}`
      );
      all.push(...page.values);
      if (page.isLast || page.values.length < limit) break;
      start += limit;
    }
    return all;
  }

  async getActiveSprint(boardId: number): Promise<JiraSprint | null> {
    const sprints = await this.getSprints(boardId, "active");
    return sprints[0] ?? null;
  }

  async getSprintById(sprintId: number): Promise<JiraSprint> {
    return this.get<JiraSprint>(`/rest/agile/1.0/sprint/${sprintId}`);
  }

  // ── Fields ──────────────────────────────────────────────────────────────

  async getFields(): Promise<JiraField[]> {
    return this.get<JiraField[]>("/rest/api/3/field");
  }

  // ── Issues ──────────────────────────────────────────────────────────────

  async getSprintIssues(sprintId: number, pointsField: string): Promise<JiraIssue[]> {
    const all: JiraIssue[] = [];
    let start = 0;
    const limit = 100;
    const fields = `summary,status,created,resolutiondate,${pointsField}`;
    while (true) {
      const page = await this.get<{ issues: JiraIssue[]; total: number }>(
        `/rest/agile/1.0/sprint/${sprintId}/issue?maxResults=${limit}&startAt=${start}&fields=${fields}`
      );
      all.push(...page.issues);
      if (all.length >= page.total || page.issues.length < limit) break;
      start += limit;
    }
    return all;
  }

  // ── Velocity ────────────────────────────────────────────────────────────
  // Uses both Agile (ISO dates) and Greenhopper (velocity numbers) APIs.

  async getVelocity(boardId: number, maxSprints = 12): Promise<VelocityEntry[]> {
    // Get the sprint list with proper ISO dates
    const closedSprints = await this.getSprints(boardId, "closed");
    const recent = closedSprints.slice(-maxSprints);

    // Get velocity stats from Greenhopper
    const ghData = await this.get<{
      sprints: Array<{ id: number; name: string; state: string }>;
      velocityStatEntries: Record<string, { estimated: { value: number }; completed: { value: number } }>;
    }>(`/rest/greenhopper/1.0/rapid/charts/velocity?rapidViewId=${boardId}`);

    const statsMap = new Map(
      Object.entries(ghData.velocityStatEntries).map(([id, v]) => [Number(id), v])
    );

    return recent
      .map((sprint) => {
        const stats = statsMap.get(sprint.id);
        return {
          sprintId: sprint.id,
          sprintName: sprint.name,
          startDate: sprint.startDate ?? "",
          endDate: sprint.completeDate ?? sprint.endDate ?? "",
          committed: stats?.estimated?.value ?? 0,
          completed: stats?.completed?.value ?? 0,
        };
      })
      .filter((e) => e.completed > 0 || e.committed > 0);
  }

  // ── Burndown ─────────────────────────────────────────────────────────────
  // Builds burndown from raw issue data (no Greenhopper needed).

  async getBurndown(
    boardId: number,
    sprintIdOrActive: "active" | number,
    pointsField: string,
    pointsFieldName: string
  ): Promise<{ points: BurndownPoint[]; meta: BurndownMeta }> {
    const sprint =
      sprintIdOrActive === "active"
        ? await this.getActiveSprint(boardId)
        : await this.getSprintById(sprintIdOrActive);

    if (!sprint) throw new Error("No active sprint found for this board");
    if (!sprint.startDate) throw new Error("Sprint has no start date");

    const issues = await this.getSprintIssues(sprint.id, pointsField);

    const sprintStart = new Date(sprint.startDate);
    const sprintEnd = new Date(sprint.endDate ?? sprint.startDate);
    const today = new Date();
    const effectiveEnd = today < sprintEnd ? today : sprintEnd;

    // Separate issues that were present at sprint start vs added mid-sprint
    const initialIssues = issues.filter(
      (i) => new Date(i.fields.created) <= sprintStart
    );
    const addedIssues = issues.filter(
      (i) => new Date(i.fields.created) > sprintStart
    );

    const getPoints = (issue: JiraIssue): number => {
      const val = issue.fields[pointsField];
      return typeof val === "number" ? val : 0;
    };

    const initialTotal = initialIssues.reduce((sum, i) => sum + getPoints(i), 0);
    const totalSprintDays = workingDaysBetween(sprintStart, sprintEnd);

    // Build day-by-day data
    const points: BurndownPoint[] = [];
    const allDays = eachCalendarDay(sprintStart, sprintEnd);

    let workingDayIndex = 0;
    let runningRemaining = initialTotal;

    // Group scope additions by day
    const addedByDay = new Map<string, number>();
    addedIssues.forEach((i) => {
      const key = toDateKey(new Date(i.fields.created));
      addedByDay.set(key, (addedByDay.get(key) ?? 0) + getPoints(i));
    });

    // Compute actual remaining per day
    const completedByDay = new Map<string, number>();
    issues.forEach((i) => {
      if (!i.fields.resolutiondate) return;
      const d = new Date(i.fields.resolutiondate);
      if (d < sprintStart) return;
      const key = toDateKey(d);
      completedByDay.set(key, (completedByDay.get(key) ?? 0) + getPoints(i));
    });

    let cumulativeCompleted = 0;
    let cumulativeAdded = 0;

    for (const day of allDays) {
      const isWeekend = day.getDay() === 0 || day.getDay() === 6;
      const isFuture = day > effectiveEnd;
      const key = toDateKey(day);

      if (!isWeekend) workingDayIndex++;

      const scopeAdded = addedByDay.get(key) ?? 0;
      cumulativeAdded += scopeAdded;
      const completedToday = completedByDay.get(key) ?? 0;
      cumulativeCompleted += completedToday;

      const currentTotal = initialTotal + cumulativeAdded;
      const actual = isFuture ? null : Math.max(0, currentTotal - cumulativeCompleted);
      const idealFraction = Math.max(0, 1 - workingDayIndex / totalSprintDays);
      const ideal = Math.round(initialTotal * idealFraction);

      points.push({
        label: `Day ${workingDayIndex}`,
        dateStr: key,
        ideal,
        actual,
        scopeAdded: scopeAdded > 0 ? scopeAdded : undefined,
        isWeekend,
        isFuture,
      });
    }

    // Linear projection from last actual point to completion
    const lastActualIdx = points.reduce((acc, p, i) => (p.actual !== null ? i : acc), -1);
    if (lastActualIdx >= 0) {
      const lastActual = points[lastActualIdx].actual!;
      const remainingDays = points.length - lastActualIdx - 1;
      if (remainingDays > 0 && lastActual > 0) {
        const dailyBurn = lastActual / (lastActualIdx + 1 || 1);
        for (let i = lastActualIdx + 1; i < points.length; i++) {
          const daysAhead = i - lastActualIdx;
          points[i].projected = Math.max(0, lastActual - dailyBurn * daysAhead);
        }
      }
    }

    const completedPoints = cumulativeCompleted;
    const remainingPoints = Math.max(0, initialTotal + cumulativeAdded - completedPoints);

    // Projected completion date
    const lastPoint = points[lastActualIdx];
    const projectedEndDate = computeProjectedEnd(lastPoint, points, lastActualIdx);

    return {
      points,
      meta: {
        sprintName: sprint.name,
        startDate: sprint.startDate,
        endDate: sprint.endDate ?? sprint.startDate,
        initialPoints: initialTotal,
        completedPoints,
        remainingPoints,
        projectedEndDate,
        pointsFieldName,
      },
    };
  }
}

// ── Date helpers ─────────────────────────────────────────────────────────

function toDateKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function eachCalendarDay(start: Date, end: Date): Date[] {
  const days: Date[] = [];
  const cur = new Date(start);
  cur.setHours(0, 0, 0, 0);
  const endNorm = new Date(end);
  endNorm.setHours(0, 0, 0, 0);
  while (cur <= endNorm) {
    days.push(new Date(cur));
    cur.setDate(cur.getDate() + 1);
  }
  return days;
}

function workingDaysBetween(start: Date, end: Date): number {
  let count = 0;
  const cur = new Date(start);
  while (cur <= end) {
    const d = cur.getDay();
    if (d !== 0 && d !== 6) count++;
    cur.setDate(cur.getDate() + 1);
  }
  return count;
}

function computeProjectedEnd(
  lastPoint: BurndownPoint | undefined,
  points: BurndownPoint[],
  lastIdx: number
): string | null {
  if (!lastPoint || lastPoint.actual === null || lastPoint.actual === 0) return null;
  const projIdx = points.findIndex((p, i) => i > lastIdx && (p.projected ?? 999) <= 0);
  if (projIdx !== -1) return points[projIdx].dateStr;
  return null;
}

// ── Factory using stored config ──────────────────────────────────────────

export function createClientFromConfig(config: {
  jiraUrl: string;
  email: string;
  apiKey: string;
}): JiraClient {
  return new JiraClient(config.jiraUrl, config.email, config.apiKey);
}
