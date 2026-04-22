import { SetupWizard } from "@/components/setup/SetupWizard";
import { readConfig } from "@/lib/config";

export default function SetupPage() {
  const config = readConfig();
  const isReconfigure = Boolean(config);

  return (
    <div className="min-h-screen bg-base flex items-center justify-center p-6">
      <div className="w-full max-w-lg">
        {/* Header */}
        <div className="flex items-center gap-3 mb-10">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-accent to-violet flex items-center justify-center text-xl font-black text-[#080D1A]">
            J
          </div>
          <div>
            <h1 className="text-2xl font-black tracking-tight text-txt">Jyra</h1>
            <p className="text-xs text-muted">Team metrics dashboard</p>
          </div>
        </div>

        <div className="bg-card border border-border rounded-2xl p-8 shadow-xl">
          <SetupWizard isReconfigure={isReconfigure} />
        </div>
      </div>
    </div>
  );
}
