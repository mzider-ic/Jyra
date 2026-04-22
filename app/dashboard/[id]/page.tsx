import { notFound, redirect } from "next/navigation";
import { readConfig } from "@/lib/config";
import { getDashboard } from "@/lib/dashboards";
import { AppShell } from "@/components/layout/AppShell";
import { DashboardClient } from "./DashboardClient";

export default function DashboardPage({ params }: { params: { id: string } }) {
  const config = readConfig();
  if (!config) redirect("/setup");

  const dashboard = getDashboard(params.id);
  if (!dashboard) notFound();

  return (
    <AppShell>
      <DashboardClient initialDashboard={dashboard} />
    </AppShell>
  );
}
