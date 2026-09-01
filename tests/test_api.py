from fastapi.testclient import TestClient
from unittest.mock import patch
from backend.main import app

client = TestClient(app)

def test_read_root():
    response = client.get("/")
    assert response.status_code == 200
    assert "SaveMedia" in response.text or "Selamat Datang" in response.text

def test_extract_media_validation():
    # Test empty payload/url
    response = client.post("/api/extract", json={"url": "   "})
    assert response.status_code == 400
    assert "detail" in response.json()

@patch("backend.main.extract_media_info")
def test_extract_media_success(mock_extract):
    mock_extract.return_value = {
        "title": "Test Video",
        "thumbnail": "https://example.com/thumb.jpg",
        "duration": "01:30",
        "uploader": "Test Channel",
        "platform": "YouTube",
        "formats": [
            {
                "format_id": "720p",
                "ext": "mp4",
                "type": "video",
                "quality": "720p (mp4)",
                "filesize": "10.5 MB",
                "url": "https://example.com/video.mp4",
                "has_video": True,
                "has_audio": True
            }
        ]
    }

    response = client.post("/api/extract", json={"url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"})
    assert response.status_code == 200
    res_json = response.json()
    assert res_json["status"] == "success"
    assert res_json["data"]["title"] == "Test Video"
    assert res_json["data"]["platform"] == "YouTube"
    assert len(res_json["data"]["formats"]) == 1

@patch("backend.main.extract_media_info")
def test_extract_media_failure(mock_extract):
    mock_extract.side_effect = ValueError("Gagal memproses URL: Unsupported URL")

    response = client.post("/api/extract", json={"url": "https://invalid-site.com/video"})
    assert response.status_code == 400
    assert "Gagal memproses URL" in response.json()["detail"]

@patch("requests.get")
def test_proxy_download_success(mock_get):
    class MockResponse:
        status_code = 200
        headers = {
            "Content-Type": "video/mp4",
            "Content-Length": "1024"
        }
        def iter_content(self, chunk_size=65536):
            yield b"dummy content"

    mock_get.return_value = MockResponse()

    response = client.get("/api/download?url=https://example.com/file.mp4&filename=test.mp4")
    assert response.status_code == 200
    assert response.headers["content-type"] == "video/mp4"
    assert 'attachment; filename="test.mp4"' in response.headers["content-disposition"]
    assert response.content == b"dummy content"
