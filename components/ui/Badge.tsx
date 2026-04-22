type BadgeVariant = "default" | "success" | "warning" | "danger" | "accent" | "violet";

const variants: Record<BadgeVariant, string> = {
  default: "bg-surface border-border text-muted",
  success: "bg-emerald/10 border-emerald/30 text-emerald",
  warning: "bg-amber/10 border-amber/30 text-amber",
  danger: "bg-rose/10 border-rose/30 text-rose",
  accent: "bg-accent/10 border-accent/30 text-accent",
  violet: "bg-violet/10 border-violet/30 text-violet",
};

export function Badge({
  children,
  variant = "default",
  className = "",
}: {
  children: React.ReactNode;
  variant?: BadgeVariant;
  className?: string;
}) {
  return (
    <span
      className={[
        "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border",
        variants[variant],
        className,
      ].join(" ")}
    >
      {children}
    </span>
  );
}
