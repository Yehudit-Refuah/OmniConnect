from dotenv import load_dotenv

load_dotenv()  # read backend/.env before anything else

from fastapi import FastAPI  # noqa: E402

from app.pbx.router import router as pbx_router  # noqa: E402

app = FastAPI(title="OmniConnect API")
app.include_router(pbx_router)


@app.get("/api/health")
def health():
    """Simple check that the API is running."""
    return {"status": "ok"}
