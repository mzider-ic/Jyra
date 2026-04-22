"use client";

import { useState } from "react";
import { Plus, PenLine, Check } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { WidgetConfigModal } from "./WidgetConfigModal";
import { VelocityWidget } from "@/components/widgets/VelocityWidget";
import { BurndownWidget } from "@/components/widgets/BurndownWidget";
import { ProjectBurnRateWidget } from "@/components/widgets/ProjectBurnRateWidget";
import type { Dashboard, Widget } from "@/types";

interface DashboardGridProps {
  dashboard: Dashboard;
  onAddWidget: (widget: Omit<Widget, "id">) => Promise<Widget>;
  onUpdateWidget: (widgetId: string, patch: Partial<Widget>) => Promise<void>;
  onRemoveWidget: (widgetId: string) => Promise<void>;
}

function WidgetRenderer({
  widget,
  onConfigure,
  onDelete,
  editMode,
}: {
  widget: Widget;
  onConfigure: () => void;
  onDelete: () => void;
  editMode: boolean;
}) {
  const props = { onConfigure, onDelete, editMode };
  if (widget.type === "velocity") {
    return <VelocityWidget config={widget.config as Parameters<typeof VelocityWidget>[0]["config"]} {...props} />;
  }
  if (widget.type === "burndown") {
    return <BurndownWidget config={widget.config as Parameters<typeof BurndownWidget>[0]["config"]} {...props} />;
  }
  if (widget.type === "project-burn-rate") {
    return <ProjectBurnRateWidget config={widget.config as Parameters<typeof ProjectBurnRateWidget>[0]["config"]} {...props} />;
  }
  return null;
}

export function DashboardGrid({ dashboard, onAddWidget, onUpdateWidget, onRemoveWidget }: DashboardGridProps) {
  const [editMode, setEditMode] = useState(false);
  const [addModalOpen, setAddModalOpen] = useState(false);
  const [configWidget, setConfigWidget] = useState<Widget | null>(null);

  async function handleAdd(widgetData: Omit<Widget, "id">) {
    await onAddWidget(widgetData);
    setAddModalOpen(false);
  }

  async function handleConfigure(widgetData: Omit<Widget, "id">) {
    if (!configWidget) return;
    await onUpdateWidget(configWidget.id, widgetData);
    setConfigWidget(null);
  }

  return (
    <div className="flex flex-col h-full">
      {/* Header bar */}
      <div className="flex items-center justify-between px-6 h-14 border-b border-border shrink-0">
        <h1 className="text-base font-semibold text-txt">{dashboard.name}</h1>
        <div className="flex items-center gap-2">
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setEditMode((v) => !v)}
            className={editMode ? "text-accent" : ""}
          >
            {editMode ? <><Check size={13} /> Done</> : <><PenLine size={13} /> Edit</>}
          </Button>
          <Button
            variant="primary"
            size="sm"
            onClick={() => setAddModalOpen(true)}
          >
            <Plus size={13} /> Add widget
          </Button>
        </div>
      </div>

      {/* Grid */}
      <div className="flex-1 overflow-y-auto p-6">
        {dashboard.widgets.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full gap-4 text-center">
            <p className="text-sm text-muted">This dashboard has no widgets yet.</p>
            <Button variant="primary" onClick={() => setAddModalOpen(true)}>
              <Plus size={14} /> Add your first widget
            </Button>
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-5 auto-rows-[340px]">
            {dashboard.widgets.map((widget) => (
              <div
                key={widget.id}
                className={widget.size === "full" ? "col-span-2" : "col-span-1"}
              >
                <WidgetRenderer
                  widget={widget}
                  onConfigure={() => setConfigWidget(widget)}
                  onDelete={() => onRemoveWidget(widget.id)}
                  editMode={editMode}
                />
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Add widget modal */}
      <WidgetConfigModal
        open={addModalOpen}
        onClose={() => setAddModalOpen(false)}
        onSave={handleAdd}
      />

      {/* Reconfigure widget modal */}
      <WidgetConfigModal
        open={Boolean(configWidget)}
        onClose={() => setConfigWidget(null)}
        onSave={handleConfigure}
        existing={configWidget ?? undefined}
      />
    </div>
  );
}
