import fs from "fs";
import path from "path";
import os from "os";
import type { Dashboard, Widget } from "@/types";

const DASHBOARDS_FILE = path.join(os.homedir(), ".config", "jyra", "dashboards.json");

function read(): Dashboard[] {
  try {
    if (!fs.existsSync(DASHBOARDS_FILE)) return [];
    return JSON.parse(fs.readFileSync(DASHBOARDS_FILE, "utf-8")) as Dashboard[];
  } catch {
    return [];
  }
}

function write(dashboards: Dashboard[]) {
  fs.writeFileSync(DASHBOARDS_FILE, JSON.stringify(dashboards, null, 2), { mode: 0o600 });
}

export function listDashboards(): Dashboard[] {
  return read();
}

export function getDashboard(id: string): Dashboard | null {
  return read().find((d) => d.id === id) ?? null;
}

export function createDashboard(name: string): Dashboard {
  const dashboards = read();
  const now = new Date().toISOString();
  const dashboard: Dashboard = {
    id: `dash-${Date.now()}`,
    name,
    widgets: [],
    createdAt: now,
    updatedAt: now,
  };
  write([...dashboards, dashboard]);
  return dashboard;
}

export function updateDashboard(id: string, patch: Partial<Pick<Dashboard, "name" | "widgets">>): Dashboard | null {
  const dashboards = read();
  const idx = dashboards.findIndex((d) => d.id === id);
  if (idx === -1) return null;
  const updated = { ...dashboards[idx], ...patch, updatedAt: new Date().toISOString() };
  dashboards[idx] = updated;
  write(dashboards);
  return updated;
}

export function deleteDashboard(id: string): boolean {
  const dashboards = read();
  const filtered = dashboards.filter((d) => d.id !== id);
  if (filtered.length === dashboards.length) return false;
  write(filtered);
  return true;
}

export function addWidget(dashboardId: string, widget: Omit<Widget, "id">): Widget | null {
  const dashboards = read();
  const dash = dashboards.find((d) => d.id === dashboardId);
  if (!dash) return null;
  const w: Widget = { ...widget, id: `widget-${Date.now()}` };
  dash.widgets.push(w);
  dash.updatedAt = new Date().toISOString();
  write(dashboards);
  return w;
}

export function removeWidget(dashboardId: string, widgetId: string): boolean {
  const dashboards = read();
  const dash = dashboards.find((d) => d.id === dashboardId);
  if (!dash) return false;
  const before = dash.widgets.length;
  dash.widgets = dash.widgets.filter((w) => w.id !== widgetId);
  if (dash.widgets.length === before) return false;
  dash.updatedAt = new Date().toISOString();
  write(dashboards);
  return true;
}

export function updateWidget(dashboardId: string, widgetId: string, patch: Partial<Widget>): Widget | null {
  const dashboards = read();
  const dash = dashboards.find((d) => d.id === dashboardId);
  if (!dash) return null;
  const idx = dash.widgets.findIndex((w) => w.id === widgetId);
  if (idx === -1) return null;
  dash.widgets[idx] = { ...dash.widgets[idx], ...patch };
  dash.updatedAt = new Date().toISOString();
  write(dashboards);
  return dash.widgets[idx];
}

export function reorderWidgets(dashboardId: string, widgetIds: string[]): Dashboard | null {
  const dashboards = read();
  const dash = dashboards.find((d) => d.id === dashboardId);
  if (!dash) return null;
  const map = new Map(dash.widgets.map((w) => [w.id, w]));
  dash.widgets = widgetIds.map((id) => map.get(id)).filter(Boolean) as Widget[];
  dash.updatedAt = new Date().toISOString();
  write(dashboards);
  return dash;
}
