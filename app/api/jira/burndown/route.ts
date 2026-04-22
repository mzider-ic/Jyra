import { NextRequest, NextResponse } from "next/server";
import { readConfig } from "@/lib/config";
import { createClientFromConfig } from "@/lib/jira";

export async function GET(req: NextRequest) {
  const config = readConfig();
  if (!config) return NextResponse.json({ error: "Not configured" }, { status: 401 });

  const boardId = Number(req.nextUrl.searchParams.get("boardId"));
  const sprintParam = req.nextUrl.searchParams.get("sprintId") ?? "active";
  const pointsField = req.nextUrl.searchParams.get("pointsField") ?? "story_points";
  const pointsFieldName = req.nextUrl.searchParams.get("pointsFieldName") ?? "Story Points";

  if (!boardId) return NextResponse.json({ error: "boardId required" }, { status: 400 });

  const sprintIdOrActive: "active" | number =
    sprintParam === "active" ? "active" : Number(sprintParam);

  try {
    const client = createClientFromConfig(config);
    const result = await client.getBurndown(boardId, sprintIdOrActive, pointsField, pointsFieldName);
    return NextResponse.json(result);
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
