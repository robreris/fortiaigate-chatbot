import httpx
from .config import settings
from .models import ChatRequest, ChatResponse, ScanMetadata


async def send_chat(request: ChatRequest) -> ChatResponse:
    payload = {
        "model": request.model or settings.model,
        "messages": [m.model_dump() for m in request.messages],
    }

    async with httpx.AsyncClient(verify=settings.ssl_verify, timeout=120.0) as client:
        response = await client.post(
            f"{settings.base_url.rstrip('/')}/v1/test",
            headers={
                "Authorization": f"Bearer {settings.api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
        )
        response.raise_for_status()

    data = response.json()

    content = ""
    choices = data.get("choices", [])
    if choices:
        content = choices[0].get("message", {}).get("content", "")

    # Extract any FortiAIGate scan metadata from response headers
    headers = response.headers
    scan = ScanMetadata(
        prompt_injection=headers.get("x-fortiaigate-prompt-injection"),
        dlp=headers.get("x-fortiaigate-dlp"),
        toxicity=headers.get("x-fortiaigate-toxicity"),
    )
    # Only include scan if at least one field is present
    has_scan = any(v is not None for v in [scan.prompt_injection, scan.dlp, scan.toxicity])

    return ChatResponse(
        content=content,
        model=data.get("model"),
        scan=scan if has_scan else None,
        usage=data.get("usage"),
    )
