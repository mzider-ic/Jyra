"use client";

import { useState, useEffect } from "react";
import {
  ComposedChart,
  Area,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ReferenceLine,
  ResponsiveContainer,
} from "recharts";
import { WidgetShell } from "@/components/dashboard/WidgetShell";
import { Badge } from "@/components/ui/Badge";
import type { ProjectBurnPoint, TeamVelocity, ProjectBurnRateWidgetConfig } from "@/types";

const TEAM_COLORS = [
  "#22D3EE", // cyan
  "#818CF8", // violet
  "#34D399", // emerald
  "#FBBF24", // amber
  "#FB923C", // orange
  "#F472B6", // pink
  "#A3E635", // lime
  "#FB7185", // rose
];

function formatPts(n: number) {
  return n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(Math.round(n));
}

interface BurnRateResponse {
  points: ProjectBurnPoint[];
  teamVelocities: TeamVelocity[];
  combinedVelocity: number;
  totalPoints: number;
  avgSprintLengthDays: number;
  estimatedSprintsRemaining: number;
}

interface TooltipProps {
  active?: boolean;
  payload?: Array<{ name: string; value: number; color: string; dataKey: string }>;
  label?: string;
  teams?: Array<{ boardId: string; name: string }>;
}

function CustomTooltip({ active, payload, label, teams }: TooltipProps) {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-card border border-border rounded-xl p-3 shadow-xl text-xs min-w-[180px]">
      <p className="font-semibold text-txt mb-2">{label}</p>
      {payload.map((p) => {
        if (p.value === null || p.value === undefined) return null;
        const team = teams?.find((t) => t.boardId === p.dataKey.replace("team_", ""));
        return (
          <div key={p.dataKey} className="flex items-center justify-between gap-4 mb-0.5">
            <span className="flex items-center gap-1.5" style={{ color: p.color }}>
              <span className="w-2 h-2 rounded-sm inline-block" style={{ background: p.color }} />
              {team?.name ?? p.name}
            </span>
            <span className="text-txt font-semibold">{formatPts(p.value)} pts</span>
          </div>
        );
      })}
    </div>
  );
}

interface ProjectBurnRateWidgetProps {
  config: ProjectBurnRateWidgetConfig;
  onConfigure?: () => void;
  onDelete?: () => void;
  editMode?: boolean;
}

export function ProjectBurnRateWidget({ config, onConfigure, onDelete, editMode }: ProjectBurnRateWidgetProps) {
  const [data, setData] = useState<BurnRateResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  function load() {
    setLoading(true);
    setError(null);
    fetch("/api/jira/project-burn-rate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ totalPoints: config.totalPoints, teams: config.teams }),
    })
      .then((r) => r.json())
      .then((d) => {
        if (d.error) throw new Error(d.error);
        setData(d);
      })
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }

  useEffect(() => { load(); }, [config.totalPoints, JSON.stringify(config.teams)]); // eslint-disable-line react-hooks/exhaustive-deps

  // Find the split between historical and projected data
  const splitIndex = data?.points.findIndex((p) => p.isFuture) ?? -1;
  const splitLabel = splitIndex !== -1 ? data?.points[splitIndex - 1]?.label : undefined;

  // Build chart data: use totalRemaining for historical, projected for future
  const chartData = data?.points.map((p) => ({
    label: p.label,
    remaining: p.totalRemaining,
    projected: p.projected,
    isFuture: p.isFuture,
    ...Object.fromEntries(
      config.teams.map((t) => [`team_${t.boardId}`, p.teamContributions[t.boardId] ?? 0])
    ),
  })) ?? [];

  const doneDate = data && data.estimatedSprintsRemaining > 0
    ? `~${data.estimatedSprintsRemaining} sprint${data.estimatedSprintsRemaining !== 1 ? "s" : ""} remaining`
    : data?.estimatedSprintsRemaining === 0 ? "Project complete!" : null;

  const completedPts = data ? data.totalPoints - (data.points.slice(-1)[0]?.totalRemaining ?? data.points.find(p => p.isFuture && p.projected !== null)?.projected ?? data.totalPoints) : 0;
  const progressPct = data ? Math.min(100, Math.round((completedPts / data.totalPoints) * 100)) : 0;

  return (
    <WidgetShell
      title={config.projectName}
      subtitle={`${config.teams.length} team${config.teams.length !== 1 ? "s" : ""} · ${formatPts(config.totalPoints)} pts total`}
      loading={loading}
      error={error}
      onConfigure={onConfigure}
      onDelete={onDelete}
      onRefresh={load}
      editMode={editMode}
      className="h-full"
    >
      {data && (
        <div className="flex flex-col gap-3 h-full">
          {/* Stats row */}
          <div className="flex items-center gap-3 flex-wrap">
            <Badge variant="accent">
              {formatPts(data.combinedVelocity)} pts/sprint combined
            </Badge>
            {doneDate && (
              <Badge variant={data.estimatedSprintsRemaining === 0 ? "success" : "default"}>
                {doneDate}
              </Badge>
            )}
            <span className="ml-auto text-xs text-subtle">{progressPct}% complete</span>
          </div>

          {/* Progress bar */}
          <div className="w-full h-1.5 bg-surface rounded-full overflow-hidden">
            <div
              className="h-full rounded-full transition-all"
              style={{
                width: `${progressPct}%`,
                background: "linear-gradient(90deg, #22D3EE, #818CF8)",
              }}
            />
          </div>

          {/* Team velocity summary */}
          <div className="flex gap-3 flex-wrap">
            {data.teamVelocities.map((tv, i) => (
              <div key={tv.boardId} className="flex items-center gap-1.5 text-xs">
                <span
                  className="w-2 h-2 rounded-full inline-block shrink-0"
                  style={{ background: TEAM_COLORS[i % TEAM_COLORS.length] }}
                />
                <span className="text-muted truncate max-w-[100px]">{tv.boardName}</span>
                <span className="text-subtle">
                  {formatPts(tv.avgVelocity)} pts/sprint
                </span>
              </div>
            ))}
          </div>

          {/* Chart */}
          <div className="flex-1 min-h-0" style={{ minHeight: 180 }}>
            <ResponsiveContainer width="100%" height="100%">
              <ComposedChart data={chartData} margin={{ top: 4, right: 8, left: -20, bottom: 4 }}>
                <defs>
                  <linearGradient id="remainingGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#22D3EE" stopOpacity={0.15} />
                    <stop offset="95%" stopColor="#22D3EE" stopOpacity={0.02} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="#1E2D47" vertical={false} />
                <XAxis
                  dataKey="label"
                  tick={{ fill: "#4A5B75", fontSize: 9 }}
                  axisLine={false}
                  tickLine={false}
                  interval="preserveStartEnd"
                />
                <YAxis
                  tick={{ fill: "#4A5B75", fontSize: 10 }}
                  axisLine={false}
                  tickLine={false}
                  width={40}
                  tickFormatter={formatPts}
                />
                <Tooltip
                  content={<CustomTooltip teams={config.teams} />}
                  cursor={{ stroke: "#2A3F5F", strokeWidth: 1 }}
                />

                {/* Divider between historical and projected */}
                {splitLabel && (
                  <ReferenceLine
                    x={splitLabel}
                    stroke="#2A3F5F"
                    strokeDasharray="4 3"
                    label={{ value: "Now", position: "insideTopRight", fill: "#4A5B75", fontSize: 9 }}
                  />
                )}

                {/* Historical remaining (area) */}
                <Area
                  dataKey="remaining"
                  stroke="#22D3EE"
                  strokeWidth={2}
                  fill="url(#remainingGrad)"
                  dot={false}
                  name="Remaining"
                  connectNulls={false}
                />

                {/* Projected remaining (dashed line) */}
                <Line
                  dataKey="projected"
                  stroke="#4A5B75"
                  strokeWidth={1.5}
                  strokeDasharray="5 4"
                  dot={false}
                  name="Projected"
                  connectNulls={false}
                />

                {/* Per-team contribution bars (stacked, historical only) */}
                {config.teams.map((team, i) => (
                  <Area
                    key={team.boardId}
                    dataKey={`team_${team.boardId}`}
                    stackId="teams"
                    stroke={TEAM_COLORS[i % TEAM_COLORS.length]}
                    fill={TEAM_COLORS[i % TEAM_COLORS.length]}
                    fillOpacity={0.12}
                    strokeWidth={0}
                    dot={false}
                    name={team.name}
                  />
                ))}
              </ComposedChart>
            </ResponsiveContainer>
          </div>
        </div>
      )}
    </WidgetShell>
  );
}
