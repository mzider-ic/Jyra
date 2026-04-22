import { NextRequest, NextResponse } from "next/server";
import {
  getDashboard,
  updateDashboard,
  deleteDashboard,
  addWidget,
  removeWidget,
  updateWidget,
  reorderWidgets,
} from "@/lib/dashboards";
import type { Widget } from "@/types";

export async function GET(_req: NextRequest, { params }: { params: { id: string } }) {
  const dash = getDashboard(params.id);
  if (!dash) return NextResponse.json({ error: "Not found" }, { status: 404 });
  return NextResponse.json(dash);
}

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  const body = await req.json() as {
    name?: string;
    widgets?: Widget[];
    addWidget?: Omit<Widget, "id">;
    removeWidget?: string;
    updateWidget?: { id: string; patch: Partial<Widget> };
    reorderWidgets?: string[];
  };

  if (body.addWidget) {
    const w = addWidget(params.id, body.addWidget);
    return w ? NextResponse.json(w) : NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  if (body.removeWidget) {
    const ok = removeWidget(params.id, body.removeWidget);
    return ok ? NextResponse.json({ ok: true }) : NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  if (body.updateWidget) {
    const w = updateWidget(params.id, body.updateWidget.id, body.updateWidget.patch);
    return w ? NextResponse.json(w) : NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  if (body.reorderWidgets) {
    const dash = reorderWidgets(params.id, body.reorderWidgets);
    return dash ? NextResponse.json(dash) : NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const dash = updateDashboard(params.id, { name: body.name, widgets: body.widgets });
  return dash ? NextResponse.json(dash) : NextResponse.json({ error: "Not found" }, { status: 404 });
}

export async function DELETE(_req: NextRequest, { params }: { params: { id: string } }) {
  const ok = deleteDashboard(params.id);
  return ok ? NextResponse.json({ ok: true }) : NextResponse.json({ error: "Not found" }, { status: 404 });
}
