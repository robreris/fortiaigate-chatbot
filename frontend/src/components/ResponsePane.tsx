import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import type { ChatResponse, ChatStatus } from "../types/chat";

interface Props {
  response: ChatResponse | null;
  status: ChatStatus;
}

function ScanBadge({ label, value }: { label: string; value?: string }) {
  if (!value) return null;
  const clean = value.toLowerCase().includes("clean") || value === "0" || value.toLowerCase() === "pass";
  return (
    <div className="flex items-center justify-between py-1">
      <span className="text-gray-400 text-xs">{label}</span>
      <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${clean ? "bg-green-900 text-green-300" : "bg-red-900 text-red-300"}`}>
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
            <div className="flex gap-1.5">
              <span className="w-2 h-2 bg-fortinet-red rounded-full animate-bounce [animation-delay:0ms]" />
              <span className="w-2 h-2 bg-fortinet-red rounded-full animate-bounce [animation-delay:150ms]" />
              <span className="w-2 h-2 bg-fortinet-red rounded-full animate-bounce [animation-delay:300ms]" />
            </div>
            <p className="text-gray-500 text-sm">Scanning &amp; generating response…</p>
          </div>
        )}

        {!response && status !== "loading" && (
          <div className="flex items-center justify-center h-full">
            <p className="text-gray-600 text-sm">Response will appear here.</p>
          </div>
        )}

        {response && (
          <div className="prose prose-invert prose-sm max-w-none text-gray-100">
            <ReactMarkdown remarkPlugins={[remarkGfm]}>
              {response.content}
            </ReactMarkdown>
          </div>
        )}
      </div>

      {/* Metadata footer */}
      {response && (
        <div className="border-t border-fortinet-gray p-4 space-y-1">
          <div className="flex items-center gap-2 mb-2">
            <div className="w-1.5 h-1.5 rounded-full bg-fortinet-red" />
            <span className="text-gray-400 text-xs font-semibold uppercase tracking-wide">
              Routed through FortiAIGate
            </span>
          </div>

          {response.scan ? (
            <div className="divide-y divide-fortinet-gray">
              <ScanBadge label="Prompt Injection" value={response.scan.prompt_injection} />
              <ScanBadge label="DLP" value={response.scan.dlp} />
              <ScanBadge label="Toxicity" value={response.scan.toxicity} />
            </div>
          ) : (
            <p className="text-gray-600 text-xs">No scan metadata in response headers.</p>
          )}

          {response.usage && (
            <div className="pt-2 flex gap-4 text-xs text-gray-600">
              {response.usage.prompt_tokens != null && (
                <span>Prompt: {response.usage.prompt_tokens} tokens</span>
              )}
              {response.usage.completion_tokens != null && (
                <span>Completion: {response.usage.completion_tokens} tokens</span>
              )}
            </div>
          )}

          {response.model && (
            <p className="text-gray-600 text-xs">Model: {response.model}</p>
          )}
        </div>
      )}
    </div>
  );
}
