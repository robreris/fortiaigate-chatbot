import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import type { ChatResponse, ChatStatus } from "../types/chat";

interface Props {
  response: ChatResponse | null;
  status: ChatStatus;
}

const InjectionIcon = () => (
  <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.75}>
    <path strokeLinecap="round" strokeLinejoin="round" d="M9.75 9.75l4.5 4.5m0-4.5l-4.5 4.5M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
  </svg>
);

const DLPIcon = () => (
  <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.75}>
    <path strokeLinecap="round" strokeLinejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />
  </svg>
);

const ToxicityIcon = () => (
  <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.75}>
    <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
  </svg>
);

function ScanBadge({ label, value, icon }: { label: string; value?: string; icon: React.ReactNode }) {
  if (!value) return null;
  const clean =
    value.toLowerCase().includes("clean") ||
    value === "0" ||
    value.toLowerCase() === "pass";
  return (
    <div className="flex items-center justify-between py-2.5">
      <div className="flex items-center gap-2">
        <span className="text-gray-500">{icon}</span>
        <span className="text-gray-400 text-xs">{label}</span>
      </div>
      <span
        className={`text-xs font-semibold px-2.5 py-0.5 rounded-full ring-1 ${
          clean
            ? "bg-green-900/40 text-green-300 ring-green-800/50"
            : "bg-red-900/40 text-red-300 ring-red-800/50"
        }`}
      >
        {value}
      </span>
    </div>
  );
}

export function ResponsePane({ response, status }: Props) {
  return (
    <div className="flex flex-col h-full">
      <div className="flex-1 overflow-y-auto p-6">
        {status === "loading" && (
          <div className="flex flex-col items-center justify-center h-full gap-4">
            <div className="flex gap-2">
              <span className="w-2.5 h-2.5 bg-fortinet-red rounded-full animate-bounce [animation-delay:0ms]" />
              <span className="w-2.5 h-2.5 bg-fortinet-red/60 rounded-full animate-bounce [animation-delay:150ms]" />
              <span className="w-2.5 h-2.5 bg-fortinet-red/30 rounded-full animate-bounce [animation-delay:300ms]" />
            </div>
            <div className="text-center">
              <p className="text-gray-400 text-sm font-medium">Processing request</p>
              <p className="text-gray-600 text-xs mt-1">Running security scan &amp; generating response…</p>
            </div>
          </div>
        )}

        {!response && status !== "loading" && (
          <div className="flex flex-col items-center justify-center h-full gap-3 text-center px-8">
            <div className="w-12 h-12 rounded-full bg-fortinet-gray/40 flex items-center justify-center">
              <svg className="w-5 h-5 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M9 12.75L11.25 15 15 9.75m-3-7.036A11.959 11.959 0 013.598 6 11.99 11.99 0 003 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285z" />
              </svg>
            </div>
            <p className="text-gray-600 text-sm">Security scan info and response will appear here.</p>
          </div>
        )}

        {response && (
          <div className="prose prose-invert prose-sm max-w-none text-gray-100 leading-relaxed">
            <ReactMarkdown remarkPlugins={[remarkGfm]}>
              {response.content}
            </ReactMarkdown>
          </div>
        )}
      </div>

      {response && (
        <div className="border-t border-fortinet-gray/60 p-4">
          <div className="flex items-center gap-2 mb-3">
            <div className="w-1.5 h-1.5 rounded-full bg-fortinet-red" />
            <span className="text-gray-500 text-[11px] font-semibold uppercase tracking-wider">
              Scan Results
            </span>
          </div>

          {response.scan ? (
            <div className="divide-y divide-fortinet-gray/50">
              <ScanBadge label="Prompt Injection" value={response.scan.prompt_injection} icon={<InjectionIcon />} />
              <ScanBadge label="DLP" value={response.scan.dlp} icon={<DLPIcon />} />
              <ScanBadge label="Toxicity" value={response.scan.toxicity} icon={<ToxicityIcon />} />
            </div>
          ) : (
            <p className="text-gray-600 text-xs">No scan metadata in response headers.</p>
          )}

          {(response.usage || response.model) && (
            <div className="mt-3 pt-3 border-t border-fortinet-gray/40 flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-600">
              {response.usage?.prompt_tokens != null && (
                <span>Prompt: {response.usage.prompt_tokens} tokens</span>
              )}
              {response.usage?.completion_tokens != null && (
                <span>Completion: {response.usage.completion_tokens} tokens</span>
              )}
              {response.model && <span>Model: {response.model}</span>}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
