import { NextRequest, NextResponse } from "next/server";
import { readConfig, writeConfig, clearConfig, toSafeConfig } from "@/lib/config";
import { createClientFromConfig } from "@/lib/jira";

export async function GET() {
  const config = readConfig();
  if (!config) return NextResponse.json({ configured: false });
  return NextResponse.json({ configured: true, ...toSafeConfig(config) });
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as { jiraUrl: string; email: string; apiKey: string };
    const { jiraUrl, email, apiKey } = body;
    if (!jiraUrl || !email || !apiKey) {
      return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
    }
    // Validate by hitting Jira
    const client = createClientFromConfig({ jiraUrl, email, apiKey });
    const me = await client.testConnection();
    const config = writeConfig({ jiraUrl, email, apiKey });
    return NextResponse.json({ ok: true, ...toSafeConfig(config), displayName: me.displayName });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: msg }, { status: 400 });
  }
}

export async function DELETE() {
  clearConfig();
  return NextResponse.json({ ok: true });
}
