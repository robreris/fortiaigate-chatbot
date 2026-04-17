import { useEffect, useState } from "react";

export function Header() {
  const [backendOk, setBackendOk] = useState<boolean | null>(null);

  useEffect(() => {
    const check = () =>
      fetch("/healthz")
        .then((r) => setBackendOk(r.ok))
        .catch(() => setBackendOk(false));

    check();
    const id = setInterval(check, 15000);
    return () => clearInterval(id);
  }, []);

  return (
    <header className="flex items-center justify-between px-6 py-3 bg-fortinet-dark border-b border-fortinet-gray">
      <div className="flex items-center gap-3">
        <div className="w-8 h-8 bg-fortinet-red rounded flex items-center justify-center text-white font-bold text-sm">
          F
        </div>
        <div>
          <span className="text-white font-semibold text-sm">FortiAIGate</span>
          <span className="text-gray-400 text-sm ml-2">Chatbot Demo</span>
        </div>
      </div>
      <div className="flex items-center gap-2 text-xs">
        <span
          className={`w-2 h-2 rounded-full ${
            backendOk === null
              ? "bg-gray-500"
              : backendOk
              ? "bg-green-400"
              : "bg-fortinet-red"
          }`}
        />
        <span className="text-gray-400">
          {backendOk === null ? "Connecting…" : backendOk ? "Backend: OK" : "Backend: Unreachable"}
        </span>
      </div>
    </header>
  );
}
