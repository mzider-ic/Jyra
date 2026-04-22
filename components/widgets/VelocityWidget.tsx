"use client";

import { useState, useCallback } from "react";
import {
  ComposedChart,
  Bar,
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
import { Modal } from "@/components/ui/Modal";
import { Badge } from "@/components/ui/Badge";
import { useApi } from "@/hooks/useApi";
import type { VelocityEntry, VelocityWidgetConfig } from "@/types";

const COMMITTED_COLOR = "#818CF8"; // violet
const COMPLETED_COLOR = "#34D399"; // emerald
const AVG_COLOR = "#FBBF24";       // amber

function sprintLabel(name: string, maxLen = 14): string {
  // Strip common prefixes like "Sprint 12 - Q3 2024" → "Spr 12"
  const short = name.replace(/sprint\s*/i, "S").replace(/\s*[-–].*$/, "");
  return short.length > maxLen ? short.slice(0, maxLen) + "…" : short;
}

function formatDate(iso: string) {
  if (!iso) return "";
  return new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

interface CustomTooltipProps {
  active?: boolean;
  payload?: Array<{ name: string; value: number; color: string }>;
  label?: string;
  entries?: VelocityEntry[];
}

function CustomTooltip({ active, payload, label, entries }: CustomTooltipProps) {
  if (!active || !payload?.length) return null;
  const entry = entries?.find((e) => sprintLabel(e.sprintName) === label);
  return (
    <div className="bg-card border border-border rounded-xl p-3 shadow-xl text-xs min-w-[160px]">
      <p className="font-semibold text-txt mb-0.5 truncate max-w-[180px]">{entry?.sprintName ?? label}</p>
      {entry && (
        <p className="text-subtle mb-2">
          {formatDate(entry.startDate)} → {formatDate(entry.endDate)}
        </p>
      )}
      {payload.map((p) => (
        <div key={p.name} className="flex items-center justify-between gap-4">
          <span className="flex items-center gap-1.5" style={{ color: p.color }}>
            <span className="w-2 h-2 rounded-sm inline-block" style={{ background: p.color }} />
            {p.name}
          </span>
          <span className="font-semibold text-txt">{p.value} pts</span>
        </div>
      ))}
      {payload.length === 2 && (
        <div className="mt-1.5 pt-1.5 border-t border-border flex justify-between text-subtle">
          <span>Delta</span>
          <span className={payload[1].value >= payload[0].value ? "text-emerald" : "text-rose"}>
            {payload[1].value >= payload[0].value ? "+" : ""}
            {payload[1].value - payload[0].value} pts
          </span>
        </div>
      )}
    </div>
  );
}

function VelocityChart({ entries, height = 260 }: { entries: VelocityEntry[]; height?: number }) {
  const avg = entries.length
    ? Math.round(entries.reduce((s, e) => s + e.completed, 0) / entries.length)
    : 0;

  const data = entries.map((e) => ({
    name: sprintLabel(e.sprintName),
    Committed: e.committed,
    Completed: e.completed,
  }));

  return (
    <div>
      <div className="flex items-center gap-3 mb-3">
        <Badge variant="violet">Avg {avg} pts</Badge>
        <span className="text-xs text-subtle">{entries.length} sprints</span>
      </div>
      <ResponsiveContainer width="100%" height={height}>
        <ComposedChart data={data} margin={{ top: 4, right: 8, left: -20, bottom: 4 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#1E2D47" vertical={false} />
          <XAxis
            dataKey="name"
            tick={{ fill: "#4A5B75", fontSize: 10 }}
            axisLine={false}
            tickLine={false}
          />
          <YAxis
            tick={{ fill: "#4A5B75", fontSize: 10 }}
            axisLine={false}
            tickLine={false}
            width={36}
          />
          <Tooltip
            content={<CustomTooltip entries={entries} />}
            cursor={{ fill: "#1E2D47", radius: 4 }}
          />
          <Legend
            iconType="square"
            iconSize={8}
            formatter={(value) => (
              <span style={{ color: "#8A9BB5", fontSize: 11 }}>{value}</span>
            )}
          />
          <ReferenceLine
            y={avg}
            stroke={AVG_COLOR}
            strokeDasharray="6 3"
            strokeWidth={1.5}
            label={{ value: `Avg ${avg}`, position: "insideTopRight", fill: AVG_COLOR, fontSize: 10 }}
          />
          <Bar dataKey="Committed" fill={COMMITTED_COLOR} radius={[3, 3, 0, 0]} maxBarSize={32} opacity={0.6} />
          <Bar dataKey="Completed" fill={COMPLETED_COLOR} radius={[3, 3, 0, 0]} maxBarSize={32} />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}

interface VelocityWidgetProps {
  config: VelocityWidgetConfig;
  onConfigure?: () => void;
  onDelete?: () => void;
  editMode?: boolean;
}

export function VelocityWidget({ config, onConfigure, onDelete, editMode }: VelocityWidgetProps) {
  const [expanded, setExpanded] = useState(false);

  const { data: compact, loading, error, refetch } = useApi<VelocityEntry[]>(
    `/api/jira/velocity/${config.boardId}?maxSprints=6`
  );
  const { data: full } = useApi<VelocityEntry[]>(
    expanded ? `/api/jira/velocity/${config.boardId}?maxSprints=12` : null
  );

  const handleExpand = useCallback(() => setExpanded(true), []);

  return (
    <>
      <WidgetShell
        title={`Velocity — ${config.boardName}`}
        subtitle="Last 6 sprints · committed vs completed"
        loading={loading}
        error={error}
        onConfigure={onConfigure}
        onDelete={onDelete}
        onRefresh={refetch}
        onExpand={handleExpand}
        editMode={editMode}
        className="h-full"
      >
        {compact && compact.length > 0 ? (
          <VelocityChart entries={compact} />
        ) : !loading && (
          <div className="flex items-center justify-center h-full text-xs text-subtle">
            No closed sprints found for this board.
          </div>
        )}
      </WidgetShell>

      <Modal
        open={expanded}
        onClose={() => setExpanded(false)}
        title={`Velocity — ${config.boardName} (last 12 sprints)`}
        size="xl"
      >
        {full ? (
          <VelocityChart entries={full} height={360} />
        ) : (
          <div className="flex items-center justify-center h-48">
            <span className="w-6 h-6 border-2 border-border border-t-accent rounded-full animate-spin" />
          </div>
        )}
      </Modal>
    </>
  );
}
