export interface Message {
  role: "user" | "assistant";
  content: string;
}

export interface ScanMetadata {
  prompt_injection?: string;
  dlp?: string;
  toxicity?: string;
}

export interface ChatResponse {
  content: string;
  model?: string;
  scan?: ScanMetadata;
  usage?: {
    prompt_tokens?: number;
    completion_tokens?: number;
    total_tokens?: number;
  };
}

export type ChatStatus = "idle" | "loading" | "error";
