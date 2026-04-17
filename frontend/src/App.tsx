import { Header } from "./components/Header";
import { ChatInput } from "./components/ChatInput";
import { ResponsePane } from "./components/ResponsePane";
import { useChat } from "./hooks/useChat";

export default function App() {
  const { messages, lastResponse, status, error, sendMessage, clearMessages } = useChat();

  return (
    <div className="flex flex-col h-screen bg-fortinet-dark text-gray-100">
      <Header />
      <div className="flex flex-1 overflow-hidden">
        {/* Left pane: conversation + input */}
        <div className="w-1/2 flex flex-col border-r border-fortinet-gray">
          <ChatInput
            messages={messages}
            status={status}
            error={error}
            onSend={sendMessage}
            onClear={clearMessages}
          />
        </div>

        {/* Right pane: response + scan metadata */}
        <div className="w-1/2 flex flex-col">
          <ResponsePane response={lastResponse} status={status} />
        </div>
      </div>
    </div>
  );
}
