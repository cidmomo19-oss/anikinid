import os
from fastapi import FastAPI, HTTPException, Query, Response
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, StreamingResponse
from pydantic import BaseModel, HttpUrl
import requests
from backend.downloader import extract_media_info

app = FastAPI(
    title="Multi-Platform Social Media Downloader API",
    description="API untuk mengunduh media gratis dari berbagai platform media sosial",
    version="1.0.0"
)

# Mounting static files
if os.path.exists("static"):
    app.mount("/static", StaticFiles(directory="static"), name="static")

class ExtractRequest(BaseModel):
    url: str

@app.get("/")
def read_root():
    if os.path.exists("static/index.html"):
        return FileResponse("static/index.html")
    return {"message": "Selamat Datang di Multi Sosmed Downloader API"}

@app.post("/api/extract")
def extract_media(payload: ExtractRequest):
    url = payload.url.strip()
    if not url:
        raise HTTPException(status_code=400, detail="URL tidak boleh kosong.")

    try:
        info = extract_media_info(url)
        return {"status": "success", "data": info}
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Terjadi kesalahan pada server: {str(e)}")

@app.get("/api/download")
def proxy_download(url: str = Query(...), filename: str = Query("media.mp4")):
    """
    Proxy endpoint to stream the target media directly to the user's browser,
    setting appropriate Content-Disposition headers for direct downloading.
    """
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        res = requests.get(url, headers=headers, stream=True, timeout=15)
        if res.status_code != 200:
            raise HTTPException(status_code=res.status_code, detail="Gagal mengunduh file dari server asal.")

        media_type = res.headers.get("Content-Type", "application/octet-stream")

        # Clean up filename for header
        safe_filename = "".join([c for c in filename if c.isalnum() or c in (" ", ".", "_", "-")]).strip() or "media.mp4"

        response_headers = {
            "Content-Disposition": f'attachment; filename="{safe_filename}"',
            "Content-Length": res.headers.get("Content-Length", "")
        }
        # Remove empty content-length if not provided
        response_headers = {k: v for k, v in response_headers.items() if v}

        def stream_content():
            for chunk in res.iter_content(chunk_size=65536):
                if chunk:
                    yield chunk

        return StreamingResponse(
            stream_content(),
            media_type=media_type,
            headers=response_headers
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Terjadi kesalahan saat mengunduh file: {str(e)}")
