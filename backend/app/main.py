from fastapi import FastAPI

app = FastAPI(title="OmniConnect API")


@app.get("/api/health")
def health():
    """Simple check that the API is running."""
    return {"status": "ok"}
