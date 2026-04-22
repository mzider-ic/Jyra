"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { LayoutDashboard, Plus, Settings, Trash2, Edit2, Check, X } from "lucide-react";
import type { Dashboard } from "@/types";

interface SidebarProps {
  dashboards: Dashboard[];
  onCreate: (name: string) => Promise<Dashboard>;
  onRename: (id: string, name: string) => Promise<void>;
  onDelete: (id: string) => Promise<void>;
}

export function Sidebar({ dashboards, onCreate, onRename, onDelete }: SidebarProps) {
  const pathname = usePathname();
  const router = useRouter();
  const [creating, setCreating] = useState(false);
  const [newName, setNewName] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState("");

  async function handleCreate() {
    const name = newName.trim();
    if (!name) return;
    const dash = await onCreate(name);
    setNewName("");
    setCreating(false);
    router.push(`/dashboard/${dash.id}`);
  }

  async function handleRename(id: string) {
    const name = editName.trim();
    if (name) await onRename(id, name);
    setEditingId(null);
  }

  async function handleDelete(id: string) {
    if (!confirm("Delete this dashboard?")) return;
    await onDelete(id);
    if (pathname === `/dashboard/${id}`) {
      const remaining = dashboards.filter((d) => d.id !== id);
      router.push(remaining.length > 0 ? `/dashboard/${remaining[0].id}` : "/dashboard");
    }
  }

  return (
    <aside className="flex flex-col w-56 min-w-[14rem] bg-surface border-r border-border h-full">
      {/* Logo */}
      <div className="flex items-center gap-2.5 px-4 h-14 border-b border-border shrink-0">
        <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-accent to-violet flex items-center justify-center font-black text-[#080D1A] text-lg">
          J
        </div>
        <span className="font-bold text-txt tracking-tight text-base">Jyra</span>
      </div>

      {/* Dashboards section */}
      <div className="flex-1 overflow-y-auto py-3 px-2">
        <div className="flex items-center justify-between px-2 mb-1">
          <span className="text-[10px] font-semibold uppercase tracking-widest text-subtle">
            Dashboards
          </span>
          <button
            onClick={() => setCreating(true)}
            className="text-subtle hover:text-accent transition-colors p-0.5 rounded"
            title="New dashboard"
          >
            <Plus size={13} />
          </button>
        </div>

        {creating && (
          <div className="flex items-center gap-1 px-2 py-1 mb-1">
            <input
              autoFocus
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") handleCreate();
                if (e.key === "Escape") { setCreating(false); setNewName(""); }
              }}
              placeholder="Dashboard name"
              className="flex-1 min-w-0 bg-card border border-border rounded text-xs text-txt px-2 py-1 focus:outline-none focus:border-accent-dim"
            />
            <button onClick={handleCreate} className="text-emerald hover:text-emerald/80">
              <Check size={13} />
            </button>
            <button onClick={() => { setCreating(false); setNewName(""); }} className="text-muted hover:text-txt">
              <X size={13} />
            </button>
          </div>
        )}

        <nav className="flex flex-col gap-0.5">
          {dashboards.map((dash) => {
            const active = pathname === `/dashboard/${dash.id}`;
            return (
              <div key={dash.id} className="group relative">
                {editingId === dash.id ? (
                  <div className="flex items-center gap-1 px-2 py-1">
                    <input
                      autoFocus
                      value={editName}
                      onChange={(e) => setEditName(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") handleRename(dash.id);
                        if (e.key === "Escape") setEditingId(null);
                      }}
                      className="flex-1 min-w-0 bg-card border border-border rounded text-xs text-txt px-2 py-1 focus:outline-none focus:border-accent-dim"
                    />
                    <button onClick={() => handleRename(dash.id)} className="text-emerald">
                      <Check size={12} />
                    </button>
                    <button onClick={() => setEditingId(null)} className="text-muted">
                      <X size={12} />
                    </button>
                  </div>
                ) : (
                  <Link
                    href={`/dashboard/${dash.id}`}
                    className={[
                      "flex items-center gap-2.5 px-2 py-1.5 rounded-lg text-sm transition-colors",
                      active
                        ? "bg-accent/10 text-accent"
                        : "text-muted hover:text-txt hover:bg-card",
                    ].join(" ")}
                  >
                    <LayoutDashboard size={13} />
                    <span className="truncate flex-1">{dash.name}</span>
                  </Link>
                )}

                {editingId !== dash.id && (
                  <div className="absolute right-1 top-1/2 -translate-y-1/2 hidden group-hover:flex items-center gap-0.5">
                    <button
                      onClick={() => { setEditingId(dash.id); setEditName(dash.name); }}
                      className="p-0.5 text-subtle hover:text-muted rounded"
                    >
                      <Edit2 size={11} />
                    </button>
                    <button
                      onClick={() => handleDelete(dash.id)}
                      className="p-0.5 text-subtle hover:text-rose rounded"
                    >
                      <Trash2 size={11} />
                    </button>
                  </div>
                )}
              </div>
            );
          })}
        </nav>
      </div>

      {/* Settings link */}
      <div className="border-t border-border px-2 py-3 shrink-0">
        <Link
          href="/setup"
          className="flex items-center gap-2.5 px-2 py-1.5 rounded-lg text-sm text-muted hover:text-txt hover:bg-card transition-colors"
        >
          <Settings size={13} />
          Settings
        </Link>
      </div>
    </aside>
  );
}
