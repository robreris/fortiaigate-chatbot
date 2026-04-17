import { useRef, useState, useEffect } from "react";
import type { Message } from "../types/chat";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

const MODELS = ["gpt-4o-mini", "gpt-4o"];

interface Props {
  messages: Message[];
  status: "idle" | "loading" | "error";
  error: string | null;
  onSend: (content: string, model: string) => void;
  onClear: () => void;
}

export function ChatInput({ messages, status, error, onSend, onClear }: Props) {
  const [input, setInput] = useState("");
  const [model, setModel] = useState(MODELS[0]);
  const bottomRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  function handleSend() {
    const trimmed = input.trim();
    if (!trimmed || status === "loading") return;
    onSend(trimmed, model);
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
      <div className="flex-1 overflow-y-auto p-4 space-y-3">
        {messages.length === 0 && (
          <div className="text-gray-500 text-sm text-center mt-8">
            Send a message to start the conversation.
          </div>
        )}
        {messages.map((msg, i) => (
          <div key={i} className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
            <div
              className={`max-w-[85%] px-4 py-2 rounded-lg text-sm ${
                msg.role === "user"
                  ? "bg-fortinet-red text-white"
                  : "bg-fortinet-gray text-gray-100"
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
          <div className="text-fortinet-red text-sm text-center">{error}</div>
        )}
        <div ref={bottomRef} />
      </div>

      {/* Input area */}
      <div className="border-t border-fortinet-gray p-4 space-y-2">
        <textarea
          ref={textareaRef}
          className="w-full bg-fortinet-gray text-gray-100 rounded-lg px-3 py-2 text-sm resize-none focus:outline-none focus:ring-1 focus:ring-fortinet-red placeholder-gray-500"
          rows={3}
          placeholder="Type a message… (Ctrl+Enter to send)"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          disabled={status === "loading"}
        />
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <label className="text-gray-500 text-xs">Model</label>
            <select
              className="bg-fortinet-gray text-gray-300 text-xs rounded px-2 py-1 focus:outline-none focus:ring-1 focus:ring-fortinet-red"
              value={model}
              onChange={(e) => setModel(e.target.value)}
              disabled={status === "loading"}
            >
              {MODELS.map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
            </select>
          </div>
          <div className="flex gap-2">
            <button
              className="text-gray-500 text-xs px-3 py-1 rounded hover:text-gray-300 transition-colors"
              onClick={onClear}
              disabled={status === "loading"}
            >
              Clear
            </button>
            <button
              className="bg-fortinet-red text-white text-xs font-semibold px-4 py-1.5 rounded hover:bg-red-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
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
