import { NextRequest, NextResponse } from "next/server";
import { readConfig } from "@/lib/config";
import { createClientFromConfig } from "@/lib/jira";
import type { ProjectBurnPoint, TeamVelocity } from "@/types";

export async function POST(req: NextRequest) {
  const config = readConfig();
  if (!config) return NextResponse.json({ error: "Not configured" }, { status: 401 });

  const body = await req.json() as {
    totalPoints: number;
    teams: Array<{ boardId: string; name: string }>;
  };

  try {
    const client = createClientFromConfig(config);

    // Fetch velocity for all teams in parallel
    const teamVelocities: TeamVelocity[] = await Promise.all(
      body.teams.map(async (team) => {
        const entries = await client.getVelocity(Number(team.boardId), 6);
        const completed = entries.map((e) => e.completed).filter((v) => v > 0);
        const avgVelocity = completed.length
          ? completed.reduce((a, b) => a + b, 0) / completed.length
          : 0;

        // Estimate sprint length from dates
        let sprintLengthDays = 14;
        if (entries.length >= 2) {
          const last = entries[entries.length - 1];
          if (last.startDate && last.endDate) {
            const diff =
              (new Date(last.endDate).getTime() - new Date(last.startDate).getTime()) /
              (1000 * 60 * 60 * 24);
            if (diff > 0) sprintLengthDays = Math.round(diff);
          }
        }

        return {
          boardId: team.boardId,
          boardName: team.name,
          avgVelocity,
          sprintLengthDays,
          lastSprints: entries,
        };
      })
    );

    const combinedVelocity = teamVelocities.reduce((sum, t) => sum + t.avgVelocity, 0);

    if (combinedVelocity === 0) {
      return NextResponse.json({ error: "No velocity data available for any team" }, { status: 422 });
    }

    // Build historical burn data (past sprints) and project forward
    // Use the team with most sprint history as the time axis
    const longestHistory = teamVelocities.reduce((best, t) =>
      t.lastSprints.length > best.lastSprints.length ? t : best
    );

    const points: ProjectBurnPoint[] = [];
    let remaining = body.totalPoints;

    // Historical sprints
    for (let i = 0; i < longestHistory.lastSprints.length; i++) {
      const sprint = longestHistory.lastSprints[i];
      const teamContributions: Record<string, number> = {};
      let totalCompleted = 0;
      for (const t of teamVelocities) {
        const entry = t.lastSprints[i];
        const completed = entry?.completed ?? 0;
        teamContributions[t.boardId] = completed;
        totalCompleted += completed;
      }
      remaining = Math.max(0, remaining - totalCompleted);
      points.push({
        label: sprint.sprintName,
        totalRemaining: remaining,
        projected: null,
        isFuture: false,
        teamContributions,
      });
    }

    // Project future sprints until remaining hits 0
    const avgSprintLength = Math.round(
      teamVelocities.reduce((s, t) => s + t.sprintLengthDays, 0) / teamVelocities.length
    );
    let futureRemaining = remaining;
    let sprintNum = 1;
    while (futureRemaining > 0 && sprintNum <= 26) {
      futureRemaining = Math.max(0, futureRemaining - combinedVelocity);
      const teamContributions: Record<string, number> = {};
      for (const t of teamVelocities) {
        teamContributions[t.boardId] = t.avgVelocity;
      }
      points.push({
        label: `Sprint +${sprintNum}`,
        totalRemaining: null,
        projected: futureRemaining,
        isFuture: true,
        teamContributions,
      });
      sprintNum++;
    }

    return NextResponse.json({
      points,
      teamVelocities,
      combinedVelocity,
      totalPoints: body.totalPoints,
      avgSprintLengthDays: avgSprintLength,
      estimatedSprintsRemaining: remaining > 0 ? Math.ceil(remaining / combinedVelocity) : 0,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
