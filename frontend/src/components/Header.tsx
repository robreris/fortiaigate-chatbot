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
    <header className="flex items-center justify-between px-6 py-3.5 bg-fortinet-dark border-b border-fortinet-gray/50 shadow-sm">
      <div className="flex items-center gap-3">
        <img src="/Fortinet-logomark-rgb-red.png" alt="Fortinet" className="h-12 w-12 rounded-xl" />
        <div className="flex items-center gap-2.5">
          <img src="/FortiAIGate-white.png" alt="FortiAIGate" className="h-7" />
          <span className="text-gray-400 text-base font-semibold">
  <a href="https://www.fortinet.com/products/fortiaigate" target="_blank" rel="noopener noreferrer" className="hover:text-white transition-colors">FortiAIGate</a>
  {" "}Chatbot Demo
</span>
        </div>
      </div>
      <div className="flex items-center gap-2">
        <div
          className={`w-2 h-2 rounded-full transition-colors ${
            backendOk === null
              ? "bg-gray-600"
              : backendOk
              ? "bg-green-400"
              : "bg-fortinet-red animate-pulse"
          }`}
        />
        <span className="text-xs text-gray-500">
          {backendOk === null ? "Connecting…" : backendOk ? "Backend connected" : "Backend unreachable"}
        </span>
      </div>
    </header>
  );
}
