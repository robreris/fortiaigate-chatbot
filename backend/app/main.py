from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import httpx

from .models import ChatRequest, ChatResponse
from .proxy import send_chat

app = FastAPI(title="FortiAIGate Chatbot API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:5173"],
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)


@app.get("/healthz")
async def healthz():
    return {"status": "ok"}


@app.post("/api/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    try:
        return await send_chat(request)
    except httpx.HTTPStatusError as e:
        try:
            body = e.response.json()
            detail = body.get("detail") or body.get("message") or body.get("error") or e.response.text
        except Exception:
            detail = e.response.text or str(e)
        raise HTTPException(status_code=e.response.status_code, detail=detail)
    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"FortiAIGate unreachable: {e}")
