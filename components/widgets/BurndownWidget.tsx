"use client";

import {
  ComposedChart,
  Line,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ReferenceLine,
  ResponsiveContainer,
} from "recharts";
import { WidgetShell } from "@/components/dashboard/WidgetShell";
import { Badge } from "@/components/ui/Badge";
import { useApi } from "@/hooks/useApi";
import type { BurndownPoint, BurndownMeta, BurndownWidgetConfig } from "@/types";

const IDEAL_COLOR = "#818CF8";
const ACTUAL_COLOR = "#22D3EE";
const PROJECTED_COLOR = "#4A5B75";
const SCOPE_COLOR = "#FB7185";
const AHEAD_COLOR = "#34D399";
const BEHIND_COLOR = "#FB7185";

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

interface BurndownResponse {
  points: BurndownPoint[];
  meta: BurndownMeta;
}

interface TooltipProps {
  active?: boolean;
  payload?: Array<{ dataKey: string; value: number; color: string }>;
  label?: string;
  points?: BurndownPoint[];
}

function CustomTooltip({ active, payload, label, points }: TooltipProps) {
  if (!active || !payload?.length) return null;
  const pt = points?.find((p) => p.label === label);
  const values: Record<string, number> = {};
  payload.forEach((p) => { if (p.value !== null && p.value !== undefined) values[p.dataKey] = p.value; });

  return (
    <div className="bg-card border border-border rounded-xl p-3 shadow-xl text-xs min-w-[160px]">
      <p className="font-semibold text-txt mb-1">{label}</p>
      {pt && <p className="text-subtle mb-2">{formatDate(pt.dateStr)}</p>}
      {"ideal" in values && (
        <div className="flex justify-between gap-4">
          <span style={{ color: IDEAL_COLOR }}>Ideal</span>
          <span className="text-txt font-semibold">{Math.round(values.ideal)} pts</span>
        </div>
      )}
      {"actual" in values && (
        <div className="flex justify-between gap-4">
          <span style={{ color: ACTUAL_COLOR }}>Actual</span>
          <span className="text-txt font-semibold">{Math.round(values.actual)} pts</span>
        </div>
      )}
      {"projected" in values && (
        <div className="flex justify-between gap-4">
          <span style={{ color: PROJECTED_COLOR }}>Projected</span>
          <span className="text-txt font-semibold">{Math.round(values.projected)} pts</span>
        </div>
      )}
      {pt?.scopeAdded && (
        <div className="mt-1.5 pt-1.5 border-t border-border flex justify-between" style={{ color: SCOPE_COLOR }}>
          <span>Scope added</span>
          <span>+{pt.scopeAdded} pts</span>
        </div>
      )}
      {("ideal" in values && "actual" in values) && (
        <div className={[
          "mt-1.5 pt-1.5 border-t border-border flex justify-between",
          values.actual <= values.ideal ? "text-emerald" : "text-rose",
        ].join(" ")}>
          <span>Status</span>
          <span>{values.actual <= values.ideal ? "Ahead" : "Behind"}</span>
        </div>
      )}
    </div>
  );
}

interface BurndownWidgetProps {
  config: BurndownWidgetConfig;
  onConfigure?: () => void;
  onDelete?: () => void;
  editMode?: boolean;
}

export function BurndownWidget({ config, onConfigure, onDelete, editMode }: BurndownWidgetProps) {
  const params = new URLSearchParams({
    boardId: config.boardId,
    sprintId: config.sprintId,
    pointsField: config.pointsField,
    pointsFieldName: config.pointsFieldName,
  });

  const { data, loading, error, refetch } = useApi<BurndownResponse>(
    `/api/jira/burndown?${params}`
  );

  const { points, meta } = data ?? {};

  // Find today's index for the reference line
  const today = new Date().toISOString().slice(0, 10);
  const todayPoint = points?.find((p) => p.dateStr === today);

  // Determine if overall ahead or behind
  const lastActual = points?.filter((p) => p.actual !== null).slice(-1)[0];
  const isAhead = lastActual && lastActual.ideal !== null
    ? lastActual.actual! <= lastActual.ideal
    : null;

  const progressPct = meta
    ? Math.round((meta.completedPoints / (meta.initialPoints || 1)) * 100)
    : 0;

  return (
    <WidgetShell
      title={`Burndown — ${config.boardName}`}
      subtitle={meta ? `${meta.sprintName} · ${meta.pointsFieldName}` : config.sprintName ?? "Active sprint"}
      loading={loading}
      error={error}
      onConfigure={onConfigure}
      onDelete={onDelete}
      onRefresh={refetch}
      editMode={editMode}
      className="h-full"
    >
      {meta && points && (
        <div className="flex flex-col gap-3 h-full">
          {/* Stats row */}
          <div className="flex items-center gap-3 flex-wrap">
            <Badge variant={isAhead === true ? "success" : isAhead === false ? "danger" : "default"}>
              {isAhead === true ? "Ahead" : isAhead === false ? "Behind" : "On Track"}
            </Badge>
            <span className="text-xs text-subtle">
              {meta.completedPoints} / {meta.initialPoints} pts · {progressPct}%
            </span>
            {meta.projectedEndDate && (
              <span className="text-xs text-subtle">
                Projected: {formatDate(meta.projectedEndDate)}
              </span>
            )}
            <span className="ml-auto text-xs text-subtle">
              {meta.remainingPoints} pts remaining
            </span>
          </div>

          {/* Progress bar */}
          <div className="w-full h-1.5 bg-surface rounded-full overflow-hidden">
            <div
              className="h-full rounded-full transition-all"
              style={{
                width: `${progressPct}%`,
                background: isAhead === false
                  ? "linear-gradient(90deg, #FB7185, #F43F5E)"
                  : "linear-gradient(90deg, #34D399, #22D3EE)",
              }}
            />
          </div>

          {/* Chart */}
          <div className="flex-1 min-h-0" style={{ minHeight: 180 }}>
            <ResponsiveContainer width="100%" height="100%">
              <ComposedChart data={points} margin={{ top: 4, right: 8, left: -20, bottom: 4 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#1E2D47" vertical={false} />
                <XAxis
                  dataKey="label"
                  tick={{ fill: "#4A5B75", fontSize: 10 }}
                  axisLine={false}
                  tickLine={false}
                  interval="preserveStartEnd"
                />
                <YAxis
                  tick={{ fill: "#4A5B75", fontSize: 10 }}
                  axisLine={false}
                  tickLine={false}
                  width={36}
                />
                <Tooltip
                  content={<CustomTooltip points={points} />}
                  cursor={{ stroke: "#2A3F5F", strokeWidth: 1 }}
                />

                {/* Shade weekend columns */}
                {points
                  .filter((p) => p.isWeekend)
                  .map((p) => (
                    <ReferenceLine
                      key={p.label}
                      x={p.label}
                      stroke="#1E2D47"
                      strokeWidth={12}
                    />
                  ))}

                {/* Today marker */}
                {todayPoint && (
                  <ReferenceLine
                    x={todayPoint.label}
                    stroke="#22D3EE"
                    strokeDasharray="4 3"
                    strokeWidth={1.5}
                    label={{ value: "Today", position: "insideTopRight", fill: "#22D3EE", fontSize: 9 }}
                  />
                )}

                {/* Ideal burndown */}
                <Line
                  dataKey="ideal"
                  stroke={IDEAL_COLOR}
                  strokeWidth={1.5}
                  strokeDasharray="5 4"
                  dot={false}
                  name="Ideal"
                  activeDot={{ r: 3 }}
                />

                {/* Actual remaining */}
                <Line
                  dataKey="actual"
                  stroke={ACTUAL_COLOR}
                  strokeWidth={2}
                  dot={false}
                  name="Actual"
                  connectNulls={false}
                  activeDot={{ r: 4, fill: ACTUAL_COLOR }}
                />

                {/* Projected */}
                <Line
                  dataKey="projected"
                  stroke={PROJECTED_COLOR}
                  strokeWidth={1.5}
                  strokeDasharray="3 3"
                  dot={false}
                  name="Projected"
                  connectNulls={false}
                />

                {/* Scope-added markers as vertical reference lines */}
                {points
                  .filter((p) => p.scopeAdded)
                  .map((p) => (
                    <ReferenceLine
                      key={`scope-${p.label}`}
                      x={p.label}
                      stroke={SCOPE_COLOR}
                      strokeWidth={1}
                      strokeDasharray="2 2"
                      label={{
                        value: `+${p.scopeAdded}`,
                        position: "top",
                        fill: SCOPE_COLOR,
                        fontSize: 9,
                      }}
                    />
                  ))}
              </ComposedChart>
            </ResponsiveContainer>
          </div>

          {/* Legend */}
          <div className="flex items-center gap-4 text-xs text-subtle flex-wrap">
            <span className="flex items-center gap-1.5">
              <span className="inline-block w-4 h-0.5 bg-violet opacity-80" style={{ borderTop: `2px dashed ${IDEAL_COLOR}` }} />
              Ideal
            </span>
            <span className="flex items-center gap-1.5">
              <span className="inline-block w-4 border-t-2" style={{ borderColor: ACTUAL_COLOR }} />
              Actual
            </span>
            <span className="flex items-center gap-1.5">
              <span className="inline-block w-4 border-t-2 border-dashed" style={{ borderColor: PROJECTED_COLOR }} />
              Projected
            </span>
            {points.some((p) => p.scopeAdded) && (
              <span className="flex items-center gap-1.5" style={{ color: SCOPE_COLOR }}>
                ↑ Scope added
              </span>
            )}
          </div>
        </div>
      )}
    </WidgetShell>
  );
}
