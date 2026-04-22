"use client";

import { useState, useEffect } from "react";
import { Modal } from "@/components/ui/Modal";
import { Button } from "@/components/ui/Button";
import { Select } from "@/components/ui/Select";
import { Input } from "@/components/ui/Input";
import { Plus, Trash2 } from "lucide-react";
import { useApi } from "@/hooks/useApi";
import type {
  JiraBoard,
  JiraSprint,
  JiraField,
  Widget,
  VelocityWidgetConfig,
  BurndownWidgetConfig,
  ProjectBurnRateWidgetConfig,
} from "@/types";

// ── Shared board selector ─────────────────────────────────────────────────

function BoardSelect({
  value,
  onChange,
  label = "Board",
}: {
  value: string;
  onChange: (boardId: string, boardName: string) => void;
  label?: string;
}) {
  const { data: boards, loading } = useApi<JiraBoard[]>("/api/jira/boards");
  return (
    <Select
      label={label}
      value={value}
      onChange={(e) => {
        const board = boards?.find((b) => String(b.id) === e.target.value);
        if (board) onChange(String(board.id), board.name);
      }}
      disabled={loading}
    >
      <option value="">— Select board —</option>
      {boards?.map((b) => (
        <option key={b.id} value={String(b.id)}>
          {b.name}
        </option>
      ))}
    </Select>
  );
}

// ── Velocity config ────────────────────────────────────────────────────────

function VelocityConfig({
  config,
  onChange,
}: {
  config: Partial<VelocityWidgetConfig>;
  onChange: (c: VelocityWidgetConfig) => void;
}) {
  return (
    <div className="flex flex-col gap-4">
      <BoardSelect
        value={config.boardId ?? ""}
        onChange={(id, name) => onChange({ boardId: id, boardName: name })}
      />
      <p className="text-xs text-subtle">
        Shows last 6 sprints by default. Click the expand icon to see last 12 sprints.
      </p>
    </div>
  );
}

// ── Burndown config ────────────────────────────────────────────────────────

function BurndownConfig({
  config,
  onChange,
}: {
  config: Partial<BurndownWidgetConfig>;
  onChange: (c: BurndownWidgetConfig) => void;
}) {
  const [boardId, setBoardId] = useState(config.boardId ?? "");
  const [boardName, setBoardName] = useState(config.boardName ?? "");
  const [sprintId, setSprintId] = useState(config.sprintId ?? "active");
  const [pointsField, setPointsField] = useState(config.pointsField ?? "story_points");
  const [pointsFieldName, setPointsFieldName] = useState(config.pointsFieldName ?? "Story Points");

  const { data: sprints } = useApi<JiraSprint[]>(
    boardId ? `/api/jira/sprints/${boardId}?state=closed` : null
  );
  const { data: fields } = useApi<JiraField[]>("/api/jira/fields");

  function emit(overrides: Partial<BurndownWidgetConfig> = {}) {
    const merged = { boardId, boardName, sprintId, pointsField, pointsFieldName, ...overrides };
    if (merged.boardId) onChange(merged as BurndownWidgetConfig);
  }

  return (
    <div className="flex flex-col gap-4">
      <BoardSelect
        value={boardId}
        onChange={(id, name) => {
          setBoardId(id); setBoardName(name);
          emit({ boardId: id, boardName: name });
        }}
      />
      <Select
        label="Sprint"
        value={sprintId}
        onChange={(e) => { setSprintId(e.target.value); emit({ sprintId: e.target.value }); }}
      >
        <option value="active">Active sprint</option>
        {sprints?.slice().reverse().slice(0, 20).map((s) => (
          <option key={s.id} value={String(s.id)}>{s.name}</option>
        ))}
      </Select>
      <Select
        label="Points field"
        value={pointsField}
        onChange={(e) => {
          const f = fields?.find((x) => x.id === e.target.value);
          setPointsField(e.target.value);
          setPointsFieldName(f?.name ?? e.target.value);
          emit({ pointsField: e.target.value, pointsFieldName: f?.name ?? e.target.value });
        }}
        hint="Select which Jira field represents story points"
      >
        <option value="story_points">Story Points (story_points)</option>
        {fields?.map((f) => (
          <option key={f.id} value={f.id}>{f.name} ({f.id})</option>
        ))}
      </Select>
    </div>
  );
}

// ── Project burn rate config ───────────────────────────────────────────────

function ProjectBurnRateConfig({
  config,
  onChange,
}: {
  config: Partial<ProjectBurnRateWidgetConfig>;
  onChange: (c: ProjectBurnRateWidgetConfig) => void;
}) {
  const [projectName, setProjectName] = useState(config.projectName ?? "");
  const [totalPoints, setTotalPoints] = useState(String(config.totalPoints ?? ""));
  const [teams, setTeams] = useState<Array<{ boardId: string; name: string }>>(config.teams ?? []);
  const { data: boards } = useApi<JiraBoard[]>("/api/jira/boards");

  function emit(overrides: Partial<ProjectBurnRateWidgetConfig> = {}) {
    const merged = { projectName, totalPoints: Number(totalPoints) || 0, teams, ...overrides };
    if (merged.projectName && merged.totalPoints > 0 && merged.teams.length > 0) {
      onChange(merged as ProjectBurnRateWidgetConfig);
    }
  }

  function addTeam() {
    setTeams((prev) => [...prev, { boardId: "", name: "" }]);
  }

  function updateTeam(i: number, boardId: string, name: string) {
    const next = teams.map((t, idx) => (idx === i ? { boardId, name } : t));
    setTeams(next);
    emit({ teams: next });
  }

  function removeTeam(i: number) {
    const next = teams.filter((_, idx) => idx !== i);
    setTeams(next);
    emit({ teams: next });
  }

  return (
    <div className="flex flex-col gap-4">
      <Input
        label="Project name"
        placeholder="Q4 Launch"
        value={projectName}
        onChange={(e) => { setProjectName(e.target.value); emit({ projectName: e.target.value }); }}
      />
      <Input
        label="Total story points"
        type="number"
        min={1}
        placeholder="500"
        value={totalPoints}
        onChange={(e) => { setTotalPoints(e.target.value); emit({ totalPoints: Number(e.target.value) }); }}
        hint="Total points across the entire project (shared pool)"
      />

      <div className="flex flex-col gap-2">
        <span className="text-sm font-medium text-muted">Teams</span>
        {teams.map((team, i) => (
          <div key={i} className="flex items-center gap-2">
            <div className="flex-1">
              <Select
                value={team.boardId}
                onChange={(e) => {
                  const board = boards?.find((b) => String(b.id) === e.target.value);
                  if (board) updateTeam(i, String(board.id), board.name);
                }}
              >
                <option value="">— Select board —</option>
                {boards?.map((b) => (
                  <option key={b.id} value={String(b.id)}>{b.name}</option>
                ))}
              </Select>
            </div>
            <button
              onClick={() => removeTeam(i)}
              className="p-2 text-subtle hover:text-rose transition-colors shrink-0"
            >
              <Trash2 size={14} />
            </button>
          </div>
        ))}
        <Button variant="ghost" size="sm" onClick={addTeam} className="w-fit">
          <Plus size={13} /> Add team
        </Button>
      </div>
    </div>
  );
}

// ── Main modal ─────────────────────────────────────────────────────────────

type WidgetTypeKey = "velocity" | "burndown" | "project-burn-rate";

interface WidgetConfigModalProps {
  open: boolean;
  onClose: () => void;
  onSave: (widget: Omit<Widget, "id">) => Promise<void>;
  existing?: Widget;
}

const TYPE_LABELS: Record<WidgetTypeKey, string> = {
  velocity: "Velocity Chart",
  burndown: "Burndown Chart",
  "project-burn-rate": "Project Burn Rate",
};

const TYPE_DESCRIPTIONS: Record<WidgetTypeKey, string> = {
  velocity: "Team velocity over last 6–12 sprints with committed vs. completed comparison.",
  burndown: "Sprint burndown with ideal line, scope changes, and projected completion.",
  "project-burn-rate": "Multi-team project progress and completion projection.",
};

export function WidgetConfigModal({ open, onClose, onSave, existing }: WidgetConfigModalProps) {
  const [type, setType] = useState<WidgetTypeKey>(existing?.type ?? "velocity");
  const [size, setSize] = useState<"half" | "full">(existing?.size ?? "half");
  const [config, setConfig] = useState<unknown>(existing?.config ?? null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setType(existing?.type ?? "velocity");
      setSize(existing?.size ?? "half");
      setConfig(existing?.config ?? null);
      setError(null);
    }
  }, [open, existing]);

  async function handleSave() {
    if (!config) { setError("Please complete the widget configuration."); return; }
    setSaving(true);
    setError(null);
    try {
      await onSave({ type, size, config: config as Widget["config"] });
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unknown error");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={existing ? "Configure Widget" : "Add Widget"}
      size="md"
    >
      <div className="flex flex-col gap-5">
        {!existing && (
          <div>
            <p className="text-xs text-subtle mb-3 font-medium uppercase tracking-widest">Widget type</p>
            <div className="grid grid-cols-1 gap-2">
              {(Object.keys(TYPE_LABELS) as WidgetTypeKey[]).map((t) => (
                <button
                  key={t}
                  onClick={() => { setType(t); setConfig(null); }}
                  className={[
                    "flex flex-col items-start gap-0.5 p-3 rounded-xl border text-left transition-colors",
                    type === t
                      ? "border-accent bg-accent/5 text-txt"
                      : "border-border text-muted hover:border-border-bright hover:text-txt",
                  ].join(" ")}
                >
                  <span className="text-sm font-semibold">{TYPE_LABELS[t]}</span>
                  <span className="text-xs text-subtle">{TYPE_DESCRIPTIONS[t]}</span>
                </button>
              ))}
            </div>
          </div>
        )}

        <div>
          <p className="text-xs text-subtle mb-3 font-medium uppercase tracking-widest">Size</p>
          <div className="flex gap-2">
            {(["half", "full"] as const).map((s) => (
              <button
                key={s}
                onClick={() => setSize(s)}
                className={[
                  "flex-1 py-2 rounded-lg border text-sm font-medium transition-colors",
                  size === s
                    ? "border-accent bg-accent/5 text-accent"
                    : "border-border text-muted hover:border-border-bright hover:text-txt",
                ].join(" ")}
              >
                {s === "half" ? "Half width" : "Full width"}
              </button>
            ))}
          </div>
        </div>

        <div>
          <p className="text-xs text-subtle mb-3 font-medium uppercase tracking-widest">Configuration</p>
          {type === "velocity" && (
            <VelocityConfig
              config={(config as Partial<VelocityWidgetConfig>) ?? {}}
              onChange={setConfig}
            />
          )}
          {type === "burndown" && (
            <BurndownConfig
              config={(config as Partial<BurndownWidgetConfig>) ?? {}}
              onChange={setConfig}
            />
          )}
          {type === "project-burn-rate" && (
            <ProjectBurnRateConfig
              config={(config as Partial<ProjectBurnRateWidgetConfig>) ?? {}}
              onChange={setConfig}
            />
          )}
        </div>

        {error && <p className="text-xs text-rose">{error}</p>}

        <div className="flex gap-3 pt-1">
          <Button variant="ghost" onClick={onClose} className="flex-1">Cancel</Button>
          <Button variant="primary" onClick={handleSave} loading={saving} className="flex-1">
            {existing ? "Save changes" : "Add widget"}
          </Button>
        </div>
      </div>
    </Modal>
  );
}
