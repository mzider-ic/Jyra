"use client";

import { Sidebar } from "./Sidebar";
import { useDashboards } from "@/hooks/useDashboards";

export function AppShell({ children }: { children: React.ReactNode }) {
  const { dashboards, create, rename, remove } = useDashboards();

  return (
    <div className="flex h-full overflow-hidden">
      <Sidebar
        dashboards={dashboards}
        onCreate={create}
        onRename={rename}
        onDelete={remove}
      />
      <main className="flex-1 overflow-y-auto bg-base">{children}</main>
    </div>
  );
}
