"use client";

import { useState, useCallback } from "react";
import { DashboardGrid } from "@/components/dashboard/DashboardGrid";
import { apiPut } from "@/hooks/useApi";
import type { Dashboard, Widget } from "@/types";

interface DashboardClientProps {
  initialDashboard: Dashboard;
}

export function DashboardClient({ initialDashboard }: DashboardClientProps) {
  const [dashboard, setDashboard] = useState<Dashboard>(initialDashboard);

  const addWidget = useCallback(async (widget: Omit<Widget, "id">): Promise<Widget> => {
    const w = await apiPut<Widget>(`/api/dashboards/${dashboard.id}`, { addWidget: widget });
    setDashboard((d) => ({ ...d, widgets: [...d.widgets, w] }));
    return w;
  }, [dashboard.id]);

  const updateWidget = useCallback(async (widgetId: string, patch: Partial<Widget>): Promise<void> => {
    const w = await apiPut<Widget>(`/api/dashboards/${dashboard.id}`, { updateWidget: { id: widgetId, patch } });
    setDashboard((d) => ({
      ...d,
      widgets: d.widgets.map((x) => (x.id === widgetId ? w : x)),
    }));
  }, [dashboard.id]);

  const removeWidget = useCallback(async (widgetId: string): Promise<void> => {
    await apiPut(`/api/dashboards/${dashboard.id}`, { removeWidget: widgetId });
    setDashboard((d) => ({ ...d, widgets: d.widgets.filter((w) => w.id !== widgetId) }));
  }, [dashboard.id]);

  return (
    <DashboardGrid
      dashboard={dashboard}
      onAddWidget={addWidget}
      onUpdateWidget={updateWidget}
      onRemoveWidget={removeWidget}
    />
  );
}
