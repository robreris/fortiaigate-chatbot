from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    base_url: str       # FORTIAIGATE_BASE_URL
    api_key: str        # FORTIAIGATE_API_KEY
    model: str = "gpt-4o-mini"  # FORTIAIGATE_MODEL
    ssl_verify: bool = True     # FORTIAIGATE_SSL_VERIFY

    model_config = {"env_prefix": "FORTIAIGATE_", "env_file": ".env"}


settings = Settings()
