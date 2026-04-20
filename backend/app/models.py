from pydantic import BaseModel


class Message(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    messages: list[Message]
    model: str | None = None
    flow_path: str = "/v1/test"


class ScanMetadata(BaseModel):
    prompt_injection: str | None = None
    dlp: str | None = None
    toxicity: str | None = None


class ChatResponse(BaseModel):
    content: str
    model: str | None = None
    scan: ScanMetadata | None = None
    usage: dict | None = None
