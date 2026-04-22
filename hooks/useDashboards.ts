"use client";

import { useState, useEffect, useCallback } from "react";
import type { Dashboard, Widget } from "@/types";
import { apiPost, apiPut, apiDelete } from "./useApi";

export function useDashboards() {
  const [dashboards, setDashboards] = useState<Dashboard[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(() => {
    setLoading(true);
    fetch("/api/dashboards")
      .then((r) => r.json())
      .then((d) => setDashboards(d))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => { load(); }, [load]);

  const create = useCallback(async (name: string): Promise<Dashboard> => {
    const dash = await apiPost<Dashboard>("/api/dashboards", { name });
    setDashboards((prev) => [...prev, dash]);
    return dash;
  }, []);

  const rename = useCallback(async (id: string, name: string): Promise<void> => {
    const updated = await apiPut<Dashboard>(`/api/dashboards/${id}`, { name });
    setDashboards((prev) => prev.map((d) => (d.id === id ? updated : d)));
  }, []);

  const remove = useCallback(async (id: string): Promise<void> => {
    await apiDelete(`/api/dashboards/${id}`);
    setDashboards((prev) => prev.filter((d) => d.id !== id));
  }, []);

  const addWidget = useCallback(async (dashboardId: string, widget: Omit<Widget, "id">): Promise<Widget> => {
    const w = await apiPut<Widget>(`/api/dashboards/${dashboardId}`, { addWidget: widget });
    setDashboards((prev) =>
      prev.map((d) => (d.id === dashboardId ? { ...d, widgets: [...d.widgets, w] } : d))
    );
    return w;
  }, []);

  const removeWidget = useCallback(async (dashboardId: string, widgetId: string): Promise<void> => {
    await apiPut(`/api/dashboards/${dashboardId}`, { removeWidget: widgetId });
    setDashboards((prev) =>
      prev.map((d) =>
        d.id === dashboardId ? { ...d, widgets: d.widgets.filter((w) => w.id !== widgetId) } : d
      )
    );
  }, []);

  const updateWidget = useCallback(async (dashboardId: string, widgetId: string, patch: Partial<Widget>): Promise<void> => {
    const w = await apiPut<Widget>(`/api/dashboards/${dashboardId}`, { updateWidget: { id: widgetId, patch } });
    setDashboards((prev) =>
      prev.map((d) =>
        d.id === dashboardId ? { ...d, widgets: d.widgets.map((x) => (x.id === widgetId ? w : x)) } : d
      )
    );
  }, []);

  const reorder = useCallback(async (dashboardId: string, widgetIds: string[]): Promise<void> => {
    const dash = await apiPut<Dashboard>(`/api/dashboards/${dashboardId}`, { reorderWidgets: widgetIds });
    setDashboards((prev) => prev.map((d) => (d.id === dashboardId ? dash : d)));
  }, []);

  return { dashboards, loading, create, rename, remove, addWidget, removeWidget, updateWidget, reorder, reload: load };
}
