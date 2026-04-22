"use client";

import { forwardRef, SelectHTMLAttributes } from "react";

interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  label?: string;
  error?: string;
  hint?: string;
}

export const Select = forwardRef<HTMLSelectElement, SelectProps>(
  ({ label, error, hint, className = "", id, children, ...rest }, ref) => {
    const selectId = id ?? label?.toLowerCase().replace(/\s+/g, "-");
    return (
      <div className="flex flex-col gap-1.5">
        {label && (
          <label htmlFor={selectId} className="text-sm font-medium text-muted">
            {label}
          </label>
        )}
        <select
          ref={ref}
          id={selectId}
          className={[
            "w-full rounded-lg border bg-surface px-3 py-2 text-sm text-txt",
            "transition-colors cursor-pointer",
            error
              ? "border-rose/50 focus:border-rose focus:outline-none"
              : "border-border focus:border-accent-dim focus:outline-none focus:ring-1 focus:ring-accent-dim/50",
            className,
          ].join(" ")}
          {...rest}
        >
          {children}
        </select>
        {error && <p className="text-xs text-rose">{error}</p>}
        {hint && !error && <p className="text-xs text-subtle">{hint}</p>}
      </div>
    );
  }
);

Select.displayName = "Select";
