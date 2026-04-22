import { NextRequest, NextResponse } from "next/server";
import { listDashboards, createDashboard } from "@/lib/dashboards";

export async function GET() {
  return NextResponse.json(listDashboards());
}

export async function POST(req: NextRequest) {
  const { name } = await req.json() as { name: string };
  if (!name?.trim()) return NextResponse.json({ error: "Name required" }, { status: 400 });
  return NextResponse.json(createDashboard(name.trim()), { status: 201 });
}
