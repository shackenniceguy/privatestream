import os
import re
import logging
from typing import Optional, Dict, Any
import httpx

logger = logging.getLogger("privatestream.tmdb")

TMDB_API_KEY = os.getenv("TMDB_API_KEY", "")
TMDB_LANGUAGE = os.getenv("TMDB_LANGUAGE", "ru-RU")
TMDB_BASE_URL = "https://api.themoviedb.org/3"
TMDB_IMAGE_BASE = "https://image.tmdb.org/t/p"

# Common noise tags in scene torrent names
NOISE_PATTERNS = [
    r"\b(2160p|1080p|1080i|720p|480p|576p|4k|uhd)\b",
    r"\b(bluray|blu-ray|bdrip|brrip|web-dl|webrip|web|hdtv|dvdrip|remux)\b",
    r"\b(x264|x265|h264|h265|hevc|avc|xvid|divx|10bit|hdr|hdr10|sdr)\b",
    r"\b(aac|ac3|dts|dts-hd|truehd|atmos|ddp5\.1|dd5\.1|mp3|flac)\b",
    r"\b(lostfilm|newstudio|hdrezka|alexfilm|aniplay|anilibria|kuraj-bambey|kubik|rarbg|yify|psa|eztv|tgx)\b",
    r"\[.*?\]",
    r"\(.*?\)",
]


def parse_filename(raw_name: str) -> Dict[str, Any]:
    """
    Parses torrent filename or directory name into clean title, year, season, and episode.
    """
    # Remove file extension
    base = os.path.splitext(raw_name)[0]
    # Replace dots, underscores, dashes with spaces
    cleaned = base.replace(".", " ").replace("_", " ").replace("-", " ")

    # Check for Series pattern (e.g., S01E05 or 1x05 or Season 1 Episode 5)
    season = None
    episode = None
    is_series = False

    s_match = re.search(r"\b[sS](\d{1,2})[eE](\d{1,2})\b", cleaned)
    if not s_match:
        s_match = re.search(r"\b(\d{1,2})x(\d{1,2})\b", cleaned)
    if not s_match:
        s_match = re.search(r"\b[sS]eason\s*(\d{1,2})\s*[eE]pisode\s*(\d{1,2})\b", cleaned, re.IGNORECASE)
    if not s_match:
        s_match = re.search(r"\bсезон\s*(\d{1,2})\s*серия\s*(\d{1,2})\b", cleaned, re.IGNORECASE)

    if s_match:
        is_series = True
        season = int(s_match.group(1))
        episode = int(s_match.group(2))
        cleaned = cleaned[:s_match.start()]
    else:
        # Check single season format: S01 or Season 1
        s_only = re.search(r"\b[sS](\d{1,2})\b|\b[sS]eason\s*(\d{1,2})\b|\bсезон\s*(\d{1,2})\b", cleaned, re.IGNORECASE)
        if s_only:
            is_series = True
            season = int(s_only.group(1) or s_only.group(2) or s_only.group(3))
            cleaned = cleaned[:s_only.start()]

    # Extract Year (1900 - 2099)
    year = None
    year_match = re.search(r"\b(19\d{2}|20\d{2})\b", cleaned)
    if year_match:
        year = int(year_match.group(1))
        # Keep title before the year
        cleaned = cleaned[:year_match.start()]

    # Strip remaining noise tags
    for pattern in NOISE_PATTERNS:
        cleaned = re.sub(pattern, "", cleaned, flags=re.IGNORECASE)

    # Clean whitespace
    title = re.sub(r"\s+", " ", cleaned).strip()
    if not title:
        title = base

    return {
        "title": title,
        "year": year,
        "season": season,
        "episode": episode,
        "is_series": is_series,
        "raw": raw_name,
    }


class TmdbClient:
    def __init__(self, api_key: Optional[str] = None, language: str = TMDB_LANGUAGE):
        self.api_key = api_key or TMDB_API_KEY
        self.language = language

    async def fetch_metadata(self, parsed_info: Dict[str, Any]) -> Dict[str, Any]:
        """
        Fetches TMDB metadata, posters, backdrops, and overview.
        Falls back to parsed values gracefully if TMDB is unconfigured or unreachable.
        """
        title = parsed_info.get("title", "Untitled")
        year = parsed_info.get("year")
        is_series = parsed_info.get("is_series", False)
        media_type = "series" if is_series else "movie"

        default_result = {
            "title": title,
            "original_title": title,
            "overview": f"Media content for {title}" + (f" ({year})" if year else ""),
            "media_type": media_type,
            "year": year,
            "season": parsed_info.get("season"),
            "episode": parsed_info.get("episode"),
            "poster_url": f"https://placehold.co/600x900/16161E/00F0FF?text={title.replace(' ', '+')}",
            "backdrop_url": f"https://placehold.co/1920x1080/0F0F14/7B2CBF?text={title.replace(' ', '+')}",
            "tmdb_id": None,
            "vote_average": 0.0,
            "genres": "Entertainment",
        }

        if not self.api_key or self.api_key == "your_tmdb_api_key_here":
            logger.info("TMDB API key not configured. Using parsed file attributes.")
            return default_result

        endpoint = "/search/tv" if is_series else "/search/movie"
        url = f"{TMDB_BASE_URL}{endpoint}"

        params = {
            "api_key": self.api_key,
            "query": title,
            "language": self.language,
            "include_adult": "true",
        }
        if year:
            if is_series:
                params["first_air_date_year"] = str(year)
            else:
                params["year"] = str(year)

        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                res = await client.get(url, params=params)
                data = res.json()
                results = data.get("results", [])

                # Fallback to English if no Russian results
                if not results and self.language != "en-US":
                    params["language"] = "en-US"
                    res = await client.get(url, params=params)
                    data = res.json()
                    results = data.get("results", [])

                if results:
                    top = results[0]
                    tmdb_id = top.get("id")
                    canonical_title = top.get("title") or top.get("name") or title
                    original_title = top.get("original_title") or top.get("original_name")
                    overview = top.get("overview") or default_result["overview"]
                    vote_average = float(top.get("vote_average", 0.0))

                    poster_path = top.get("poster_path")
                    poster_url = f"{TMDB_IMAGE_BASE}/w780{poster_path}" if poster_path else default_result["poster_url"]

                    backdrop_path = top.get("backdrop_path")
                    backdrop_url = f"{TMDB_IMAGE_BASE}/original{backdrop_path}" if backdrop_path else default_result["backdrop_url"]

                    # Fetch detailed genres
                    genres = await self._fetch_genres(client, tmdb_id, is_series)

                    return {
                        "title": canonical_title,
                        "original_title": original_title,
                        "overview": overview,
                        "media_type": media_type,
                        "year": year or (int(top.get("release_date", "0000")[:4]) if top.get("release_date") else None),
                        "season": parsed_info.get("season"),
                        "episode": parsed_info.get("episode"),
                        "poster_url": poster_url,
                        "backdrop_url": backdrop_url,
                        "tmdb_id": tmdb_id,
                        "vote_average": vote_average,
                        "genres": genres,
                    }

            except Exception as e:
                logger.error(f"Error querying TMDB API for '{title}': {e}")

        return default_result

    async def _fetch_genres(self, client: httpx.AsyncClient, tmdb_id: int, is_series: bool) -> str:
        """Fetches detailed genre names from TMDB detail endpoint."""
        try:
            detail_endpoint = f"/tv/{tmdb_id}" if is_series else f"/movie/{tmdb_id}"
            res = await client.get(
                f"{TMDB_BASE_URL}{detail_endpoint}",
                params={"api_key": self.api_key, "language": self.language},
            )
            if res.status_code == 200:
                data = res.json()
                genre_names = [g["name"] for g in data.get("genres", []) if "name" in g]
                if genre_names:
                    return ", ".join(genre_names)
        except Exception as e:
            logger.warning(f"Failed to fetch genres for TMDB ID {tmdb_id}: {e}")
        return "Cinema"
