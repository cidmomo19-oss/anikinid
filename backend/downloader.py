import yt_dlp
import re
from typing import Dict, Any, List, Optional

def detect_platform(url: str) -> str:
    url_lower = url.lower()
    if 'youtube.com' in url_lower or 'youtu.be' in url_lower:
        return 'YouTube'
    elif 'tiktok.com' in url_lower:
        return 'TikTok'
    elif 'instagram.com' in url_lower:
        return 'Instagram'
    elif 'twitter.com' in url_lower or 'x.com' in url_lower:
        return 'Twitter / X'
    elif 'facebook.com' in url_lower or 'fb.watch' in url_lower:
        return 'Facebook'
    elif 'pinterest.com' in url_lower or 'pin.it' in url_lower:
        return 'Pinterest'
    elif 'soundcloud.com' in url_lower:
        return 'SoundCloud'
    elif 'reddit.com' in url_lower:
        return 'Reddit'
    else:
        return 'Social Media'

def format_bytes(bytes_num: Optional[int]) -> str:
    if not bytes_num:
        return 'N/A'
    for unit in ['B', 'KB', 'MB', 'GB']:
        if bytes_num < 1024.0:
            return f"{bytes_num:.1f} {unit}"
        bytes_num /= 1024.0
    return f"{bytes_num:.1f} TB"

def format_duration(seconds: Optional[int]) -> str:
    if not seconds:
        return 'N/A'
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    if h > 0:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"

def extract_media_info(url: str) -> Dict[str, Any]:
    ydl_opts = {
        'quiet': True,
        'no_warnings': True,
        'no_color': True,
        'extract_flat': False,
        'skip_download': True,
        'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    }

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        try:
            info = ydl.extract_info(url, download=False)
        except Exception as e:
            raise ValueError(f"Gagal memproses URL: {str(e)}")

    if not info:
        raise ValueError("Tidak dapat menemukan informasi media dari URL ini.")

    # Handle playlist/multi-entry if returned
    if 'entries' in info and info['entries']:
        # Pick the first valid entry if entries list exists
        info = next((item for item in info['entries'] if item), info)

    title = info.get('title') or 'Media Downloader'
    thumbnail = info.get('thumbnail') or info.get('thumbnails', [{}])[-1].get('url', '')
    duration = format_duration(info.get('duration'))
    uploader = info.get('uploader') or info.get('uploader_id') or info.get('channel') or 'Unknown'
    platform = detect_platform(url)

    formats_list = []
    seen_qualities = set()

    # Process yt-dlp formats
    raw_formats = info.get('formats', [])

    # Filter and normalize formats
    if raw_formats:
        for fmt in raw_formats:
            fmt_id = fmt.get('format_id')
            ext = fmt.get('ext', 'mp4')
            vcodec = fmt.get('vcodec', 'none')
            acodec = fmt.get('acodec', 'none')
            height = fmt.get('height')
            format_note = fmt.get('format_note', '')
            filesize = fmt.get('filesize') or fmt.get('filesize_approx')
            download_url = fmt.get('url')

            if not download_url:
                continue

            has_video = vcodec != 'none'
            has_audio = acodec != 'none'

            # Build readable quality label
            if has_video:
                if height:
                    quality_label = f"{height}p ({ext})"
                elif format_note:
                    quality_label = f"{format_note} ({ext})"
                else:
                    quality_label = f"Video ({ext})"
                media_type = "video"
            elif has_audio:
                quality_label = f"Audio ({fmt.get('abr', '128')}kbps {ext})"
                media_type = "audio"
            else:
                continue

            dedup_key = f"{media_type}_{quality_label}"
            if dedup_key in seen_qualities:
                continue
            seen_qualities.add(dedup_key)

            formats_list.append({
                'format_id': fmt_id,
                'ext': ext,
                'type': media_type,
                'quality': quality_label,
                'filesize': format_bytes(filesize),
                'url': download_url,
                'has_video': has_video,
                'has_audio': has_audio
            })

    # Fallback if yt-dlp extracted direct url without format breakdown
    if not formats_list and info.get('url'):
        formats_list.append({
            'format_id': 'default',
            'ext': info.get('ext', 'mp4'),
            'type': 'video',
            'quality': 'Standard Quality',
            'filesize': 'N/A',
            'url': info.get('url'),
            'has_video': True,
            'has_audio': True
        })

    # Sort formats (Video HD first, then lower res, then audio)
    formats_list.reverse()

    return {
        'title': title,
        'thumbnail': thumbnail,
        'duration': duration,
        'uploader': uploader,
        'platform': platform,
        'formats': formats_list[:10]  # Limit to top 10 relevant formats
    }
