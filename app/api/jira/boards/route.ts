import { NextResponse } from "next/server";
import { readConfig } from "@/lib/config";
import { createClientFromConfig } from "@/lib/jira";

export async function GET() {
  const config = readConfig();
  if (!config) return NextResponse.json({ error: "Not configured" }, { status: 401 });
  try {
    const client = createClientFromConfig(config);
    const boards = await client.getBoards();
    return NextResponse.json(boards);
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
