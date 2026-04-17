import { useState } from "react";
import type { Message, ChatResponse, ChatStatus, ScanMetadata } from "../types/chat";

export function useChat() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [lastResponse, setLastResponse] = useState<ChatResponse | null>(null);
  const [status, setStatus] = useState<ChatStatus>("idle");
  const [error, setError] = useState<string | null>(null);

  async function sendMessage(content: string, model: string) {
    const userMessage: Message = { role: "user", content };
    const nextMessages = [...messages, userMessage];

    setMessages(nextMessages);
    setStatus("loading");
    setError(null);
    setLastResponse(null);

    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ messages: nextMessages, model }),
      });

      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail ?? `Request failed: ${res.status}`);
      }

      const data: ChatResponse = await res.json();
      setLastResponse(data);
      setMessages([...nextMessages, { role: "assistant", content: data.content }]);
      setStatus("idle");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unknown error");
      setStatus("error");
    }
  }

  function clearMessages() {
    setMessages([]);
    setLastResponse(null);
    setStatus("idle");
    setError(null);
  }

  return { messages, lastResponse, status, error, sendMessage, clearMessages };
}
