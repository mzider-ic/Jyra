import { AppShell } from "@/components/layout/AppShell";
import { readConfig } from "@/lib/config";
import { redirect } from "next/navigation";
import { LayoutDashboard } from "lucide-react";

export default function DashboardIndexPage() {
  const config = readConfig();
  if (!config) redirect("/setup");

  return (
    <AppShell>
      <div className="flex flex-col items-center justify-center h-full gap-4 text-center p-8">
        <div className="w-14 h-14 rounded-2xl bg-surface border border-border flex items-center justify-center">
          <LayoutDashboard size={24} className="text-muted" />
        </div>
        <h2 className="text-lg font-semibold text-txt">No dashboards yet</h2>
        <p className="text-sm text-muted max-w-xs">
          Use the sidebar to create your first dashboard, then add widgets to visualize your team&apos;s metrics.
        </p>
      </div>
    </AppShell>
  );
}
