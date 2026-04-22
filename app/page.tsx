import { redirect } from "next/navigation";
import { readConfig } from "@/lib/config";
import { listDashboards } from "@/lib/dashboards";

export default function RootPage() {
  const config = readConfig();
  if (!config) redirect("/setup");
  const dashboards = listDashboards();
  if (dashboards.length === 0) redirect("/dashboard");
  redirect(`/dashboard/${dashboards[0].id}`);
}
