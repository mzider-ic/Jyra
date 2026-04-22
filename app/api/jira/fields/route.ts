import { NextResponse } from "next/server";
import { readConfig } from "@/lib/config";
import { createClientFromConfig } from "@/lib/jira";

export async function GET() {
  const config = readConfig();
  if (!config) return NextResponse.json({ error: "Not configured" }, { status: 401 });
  try {
    const client = createClientFromConfig(config);
    const fields = await client.getFields();
    // Return only numeric/point-like fields
    const numeric = fields.filter(
      (f) =>
        f.schema?.type === "number" ||
        f.name.toLowerCase().includes("point") ||
        f.name.toLowerCase().includes("estimate") ||
        f.name.toLowerCase().includes("size")
    );
    return NextResponse.json(numeric);
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
