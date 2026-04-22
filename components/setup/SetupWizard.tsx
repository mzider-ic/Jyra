"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { CheckCircle2, ExternalLink, AlertCircle, ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { Input } from "@/components/ui/Input";

type Step = "credentials" | "testing" | "done";

export function SetupWizard({ isReconfigure = false }: { isReconfigure?: boolean }) {
  const router = useRouter();
  const [step, setStep] = useState<Step>("credentials");
  const [form, setForm] = useState({ jiraUrl: "", email: "", apiKey: "" });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [testing, setTesting] = useState(false);
  const [testError, setTestError] = useState<string | null>(null);
  const [displayName, setDisplayName] = useState<string | null>(null);

  function validate() {
    const e: Record<string, string> = {};
    if (!form.jiraUrl.trim()) e.jiraUrl = "Required";
    else if (!form.jiraUrl.startsWith("http")) e.jiraUrl = "Must be a full URL (https://...)";
    if (!form.email.trim()) e.email = "Required";
    else if (!form.email.includes("@")) e.email = "Must be a valid email";
    if (!form.apiKey.trim()) e.apiKey = "Required";
    setErrors(e);
    return Object.keys(e).length === 0;
  }

  async function handleSave() {
    if (!validate()) return;
    setTesting(true);
    setTestError(null);
    setStep("testing");
    try {
      const res = await fetch("/api/config", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          jiraUrl: form.jiraUrl.replace(/\/+$/, ""),
          email: form.email,
          apiKey: form.apiKey,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Connection failed");
      setDisplayName(data.displayName ?? form.email);
      setStep("done");
    } catch (err) {
      setTestError(err instanceof Error ? err.message : "Unknown error");
      setStep("credentials");
    } finally {
      setTesting(false);
    }
  }

  if (step === "done") {
    return (
      <div className="flex flex-col items-center gap-6 py-8 text-center">
        <div className="w-14 h-14 rounded-full bg-emerald/10 border border-emerald/30 flex items-center justify-center">
          <CheckCircle2 size={28} className="text-emerald" />
        </div>
        <div>
          <h2 className="text-xl font-bold text-txt mb-1">Connected!</h2>
          <p className="text-sm text-muted">
            Logged in as <span className="text-txt font-medium">{displayName}</span>
          </p>
        </div>
        <Button variant="primary" size="lg" onClick={() => router.push("/dashboard")}>
          Go to Dashboard <ArrowRight size={16} />
        </Button>
      </div>
    );
  }

  if (step === "testing") {
    return (
      <div className="flex flex-col items-center gap-4 py-12">
        <span className="w-10 h-10 rounded-full border-2 border-border border-t-accent animate-spin" />
        <p className="text-sm text-muted">Connecting to Jira…</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6 max-w-md">
      <div>
        <h2 className="text-xl font-bold text-txt mb-1">
          {isReconfigure ? "Update Jira Connection" : "Connect to Jira"}
        </h2>
        <p className="text-sm text-muted">
          Credentials are stored locally in{" "}
          <code className="text-accent text-xs bg-surface px-1.5 py-0.5 rounded">~/.config/jyra/config.json</code>{" "}
          with restricted file permissions.
        </p>
      </div>

      <div className="flex flex-col gap-4">
        <Input
          label="Jira URL"
          placeholder="https://yourcompany.atlassian.net"
          value={form.jiraUrl}
          onChange={(e) => setForm((f) => ({ ...f, jiraUrl: e.target.value }))}
          error={errors.jiraUrl}
          hint="Your Jira Cloud base URL, no trailing slash"
        />
        <Input
          label="Email Address"
          type="email"
          placeholder="you@company.com"
          value={form.email}
          onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))}
          error={errors.email}
        />
        <Input
          label="API Token"
          type="password"
          placeholder="ATATT3xFfGF0..."
          value={form.apiKey}
          onChange={(e) => setForm((f) => ({ ...f, apiKey: e.target.value }))}
          error={errors.apiKey}
          hint="Generate at id.atlassian.com → Security → API tokens"
        />
      </div>

      <a
        href="https://id.atlassian.com/manage-profile/security/api-tokens"
        target="_blank"
        rel="noopener noreferrer"
        className="inline-flex items-center gap-1.5 text-xs text-accent hover:text-accent/80 transition-colors"
      >
        Get an API token <ExternalLink size={11} />
      </a>

      {testError && (
        <div className="flex items-start gap-2.5 p-3 rounded-lg bg-rose/10 border border-rose/20 text-rose text-sm">
          <AlertCircle size={16} className="shrink-0 mt-0.5" />
          {testError}
        </div>
      )}

      <Button
        variant="primary"
        size="lg"
        onClick={handleSave}
        loading={testing}
        className="w-full"
      >
        {testing ? "Testing connection…" : "Save & Connect"}
      </Button>
    </div>
  );
}
