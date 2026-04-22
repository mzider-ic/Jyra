"use client";

import { forwardRef, InputHTMLAttributes } from "react";

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
  hint?: string;
}

export const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ label, error, hint, className = "", id, ...rest }, ref) => {
    const inputId = id ?? label?.toLowerCase().replace(/\s+/g, "-");
    return (
      <div className="flex flex-col gap-1.5">
        {label && (
          <label htmlFor={inputId} className="text-sm font-medium text-muted">
            {label}
          </label>
        )}
        <input
          ref={ref}
          id={inputId}
          className={[
            "w-full rounded-lg border bg-surface px-3 py-2 text-sm text-txt placeholder:text-subtle",
            "transition-colors",
            error
              ? "border-rose/50 focus:border-rose focus:outline-none"
              : "border-border focus:border-accent-dim focus:outline-none focus:ring-1 focus:ring-accent-dim/50",
            className,
          ].join(" ")}
          {...rest}
        />
        {error && <p className="text-xs text-rose">{error}</p>}
        {hint && !error && <p className="text-xs text-subtle">{hint}</p>}
      </div>
    );
  }
);

Input.displayName = "Input";
