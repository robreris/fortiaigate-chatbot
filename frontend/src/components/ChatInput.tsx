import { useRef, useState, useEffect } from "react";
import type { Message } from "../types/chat";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

interface Props {
  messages: Message[];
  status: "idle" | "loading" | "error";
  error: string | null;
  onSend: (content: string, flowPath: string) => void;
  onClear: () => void;
}

export function ChatInput({ messages, status, error, onSend, onClear }: Props) {
  const [input, setInput] = useState("");
  const [flowPath, setFlowPath] = useState("/v1/openai-demo");
  const bottomRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  function handleSend() {
    const trimmed = input.trim();
    if (!trimmed || status === "loading") return;
    onSend(trimmed, flowPath);
    setInput("");
    textareaRef.current?.focus();
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      handleSend();
    }
  }

  return (
    <div className="flex flex-col h-full">
      {/* Conversation history */}
      <div className="flex-1 overflow-y-auto px-4 py-5 space-y-4">
        {messages.length === 0 && (
          <div className="flex flex-col items-center justify-center h-full gap-3 text-center px-8 pb-8">
            <div className="w-12 h-12 rounded-full bg-fortinet-gray/60 flex items-center justify-center">
              <svg className="w-5 h-5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M7.5 8.25h9m-9 3H12m-9.75 1.51c0 1.6 1.123 2.994 2.707 3.227 1.129.166 2.27.293 3.423.379.35.026.67.21.865.501L12 21l2.755-4.133a1.14 1.14 0 01.865-.501 48.172 48.172 0 003.423-.379c1.584-.233 2.707-1.626 2.707-3.228V6.741c0-1.602-1.123-2.995-2.707-3.228A48.394 48.394 0 0012 3c-2.392 0-4.744.175-7.043.513C3.373 3.746 2.25 5.14 2.25 6.741v6.018z" />
              </svg>
            </div>
            <p className="text-gray-400 text-sm">Send a message to start the conversation.</p>
            <p className="text-gray-600 text-xs leading-relaxed">
              Messages are scanned by FortiAIGate before reaching the LLM.
            </p>
          </div>
        )}

        {messages.map((msg, i) => (
          <div key={i} className={`flex flex-col ${msg.role === "user" ? "items-end" : "items-start"}`}>
            <span className="text-[11px] text-gray-600 mb-1 px-1 font-medium">
              {msg.role === "user" ? "You" : "AI"}
            </span>
            <div
              className={`max-w-[85%] px-4 py-2.5 text-sm shadow-sm ${
                msg.role === "user"
                  ? "bg-fortinet-red text-white rounded-2xl rounded-tr-sm"
                  : "bg-fortinet-gray text-gray-100 rounded-2xl rounded-tl-sm"
              }`}
            >
              {msg.role === "assistant" ? (
                <ReactMarkdown remarkPlugins={[remarkGfm]} className="prose prose-invert prose-sm max-w-none">
                  {msg.content}
                </ReactMarkdown>
              ) : (
                msg.content
              )}
            </div>
          </div>
        ))}

        {error && (
          <div className="rounded-xl border border-red-900/50 bg-red-950/25 px-4 py-3">
            <div className="flex gap-3">
              <svg className="w-4 h-4 text-red-400 mt-0.5 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
              </svg>
              <div>
                <p className="text-red-300 text-sm font-semibold">Request failed</p>
                <p className="text-red-400/70 text-xs mt-0.5 break-words">{error}</p>
                <p className="text-gray-500 text-xs mt-2 leading-relaxed">
                  Check that the{" "}
                  <span className="text-gray-300 font-medium">Flow path</span>{" "}
                  (bottom-left) matches an AI flow configured on your FortiAIGate instance.
                </p>
              </div>
            </div>
          </div>
        )}

        <div ref={bottomRef} />
      </div>

      {/* Input area */}
      <div className="border-t border-fortinet-gray/60 p-4 space-y-2.5">
        <textarea
          ref={textareaRef}
          className="w-full bg-fortinet-gray/70 text-gray-100 rounded-xl px-3.5 py-2.5 text-sm resize-none focus:outline-none focus:ring-1 focus:ring-fortinet-red/60 placeholder-gray-600 transition-shadow"
          rows={3}
          placeholder="Type a message… (Ctrl+Enter to send)"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          disabled={status === "loading"}
        />
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <label className="text-gray-600 text-[11px] font-semibold uppercase tracking-wider">Flow</label>
            <input
              type="text"
              className="bg-fortinet-gray/50 text-gray-300 text-xs rounded-lg px-2.5 py-1.5 w-40 focus:outline-none focus:ring-1 focus:ring-fortinet-red/50 placeholder-gray-600 font-mono"
              value={flowPath}
              onChange={(e) => setFlowPath(e.target.value)}
              disabled={status === "loading"}
              placeholder="/v1/openai-demo"
              spellCheck={false}
            />
          </div>
          <div className="flex items-center gap-2">
            <button
              className="text-gray-600 text-xs px-3 py-1.5 rounded-lg hover:text-gray-300 hover:bg-fortinet-gray/40 transition-colors disabled:opacity-40"
              onClick={onClear}
              disabled={status === "loading"}
            >
              Clear
            </button>
            <button
              className="bg-fortinet-red text-white text-xs font-semibold px-4 py-1.5 rounded-lg hover:bg-red-600 active:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors shadow-sm"
              onClick={handleSend}
              disabled={status === "loading" || !input.trim()}
            >
              {status === "loading" ? "Sending…" : "Send →"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
