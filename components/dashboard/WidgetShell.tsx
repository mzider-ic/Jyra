"use client";

import { useState, ReactNode } from "react";
import { Settings, Trash2, RefreshCw, Maximize2 } from "lucide-react";
import { Spinner } from "@/components/ui/Spinner";

interface WidgetShellProps {
  title: string;
  subtitle?: string;
  loading?: boolean;
  error?: string | null;
  onConfigure?: () => void;
  onDelete?: () => void;
  onRefresh?: () => void;
  onExpand?: () => void;
  children: ReactNode;
  className?: string;
  editMode?: boolean;
}

export function WidgetShell({
  title,
  subtitle,
  loading,
  error,
  onConfigure,
  onDelete,
  onRefresh,
  onExpand,
  children,
  className = "",
  editMode = false,
}: WidgetShellProps) {
  const [hovering, setHovering] = useState(false);

  return (
    <div
      className={[
        "widget-card flex flex-col bg-card border border-border rounded-2xl overflow-hidden",
        className,
      ].join(" ")}
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
    >
      {/* Header */}
      <div className="flex items-center justify-between px-5 pt-4 pb-3 shrink-0">
        <div className="min-w-0">
          <h3 className="text-sm font-semibold text-txt truncate">{title}</h3>
          {subtitle && <p className="text-xs text-subtle mt-0.5">{subtitle}</p>}
        </div>

        <div
          className={[
            "flex items-center gap-1 transition-opacity duration-150",
            hovering || editMode ? "opacity-100" : "opacity-0",
          ].join(" ")}
        >
          {onRefresh && (
            <button
              onClick={onRefresh}
              className="p-1.5 rounded-md text-subtle hover:text-muted hover:bg-surface transition-colors"
              title="Refresh"
            >
              <RefreshCw size={12} />
            </button>
          )}
          {onExpand && (
            <button
              onClick={onExpand}
              className="p-1.5 rounded-md text-subtle hover:text-muted hover:bg-surface transition-colors"
              title="Expand"
            >
              <Maximize2 size={12} />
            </button>
          )}
          {onConfigure && (
            <button
              onClick={onConfigure}
              className="p-1.5 rounded-md text-subtle hover:text-muted hover:bg-surface transition-colors"
              title="Configure"
            >
              <Settings size={12} />
            </button>
          )}
          {onDelete && editMode && (
            <button
              onClick={onDelete}
              className="p-1.5 rounded-md text-subtle hover:text-rose hover:bg-rose/10 transition-colors"
              title="Remove widget"
            >
              <Trash2 size={12} />
            </button>
          )}
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 min-h-0 px-5 pb-5">
        {loading ? (
          <div className="h-full flex items-center justify-center">
            <Spinner size="lg" />
          </div>
        ) : error ? (
          <div className="h-full flex flex-col items-center justify-center gap-2 text-center">
            <p className="text-xs text-rose">{error}</p>
            {onRefresh && (
              <button
                onClick={onRefresh}
                className="text-xs text-muted hover:text-txt underline transition-colors"
              >
                Retry
              </button>
            )}
          </div>
        ) : (
          children
        )}
      </div>
    </div>
  );
}
