import { NextRequest, NextResponse } from "next/server";
import { readConfig } from "@/lib/config";
import { createClientFromConfig } from "@/lib/jira";

export async function GET(req: NextRequest, { params }: { params: { boardId: string } }) {
  const config = readConfig();
  if (!config) return NextResponse.json({ error: "Not configured" }, { status: 401 });
  const boardId = Number(params.boardId);
  const state = req.nextUrl.searchParams.get("state") as "active" | "closed" | "future" | null;
  try {
    const client = createClientFromConfig(config);
    const sprints = await client.getSprints(boardId, state ?? undefined);
    return NextResponse.json(sprints);
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
