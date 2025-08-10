import requests
import logging
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional
import time
import os
from playwright.async_api import async_playwright
import asyncio


class HackerNewsFetcher:
    def __init__(self):
        """Initialize Hacker News fetcher for personal favorites"""
        self.base_url = os.getenv(
            "LOOM_HACKERNEWS_API_URL", "https://hacker-news.firebaseio.com/v0"
        )
        self.hn_base_url = os.getenv(
            "LOOM_HACKERNEWS_BASE_URL", "https://news.ycombinator.com"
        )
        self.username = os.getenv("LOOM_HACKERNEWS_USERNAME")
        self.password = os.getenv("LOOM_HACKERNEWS_PASSWORD")
        self.max_items = int(os.getenv("LOOM_HACKERNEWS_MAX_ITEMS", "50"))
        self.use_browser = (
            os.getenv("LOOM_HACKERNEWS_USE_BROWSER", "true").lower() == "true"
        )

        if not self.username:
            raise ValueError(
                "LOOM_HACKERNEWS_USERNAME environment variable is required"
            )

        self.session = requests.Session()
        self.session.headers.update(
            {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
            }
        )

        # Rate limiting - respect HN
        self.last_request_time = 0
        self.min_request_interval = float(
            os.getenv("LOOM_HACKERNEWS_RATE_LIMIT_SECONDS", "0.5")
        )

        # Browser setup for scraping
        self.playwright_instance = None
        self.browser = None
        self.context = None

    def _rate_limit(self):
        """Ensure we don't make requests too quickly"""
        current_time = time.time()
        time_since_last = current_time - self.last_request_time
        if time_since_last < self.min_request_interval:
            time.sleep(self.min_request_interval - time_since_last)
        self.last_request_time = time.time()

    def _make_request(self, endpoint: str) -> Optional[Any]:
        """Make a rate-limited request to HN API"""
        self._rate_limit()

        try:
            url = f"{self.base_url}/{endpoint}"
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logging.error(f"Error making request to {endpoint}: {e}")
            return None

    async def setup_browser(self):
        """Setup browser for web scraping"""
        if not self.playwright_instance:
            self.playwright_instance = await async_playwright().start()
            self.browser = await self.playwright_instance.chromium.launch(headless=True)
            self.context = await self.browser.new_context(
                viewport={"width": 1280, "height": 720},
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
            )

    async def login_to_hn(self):
        """Login to Hacker News if credentials are provided"""
        if not self.password:
            logging.warning("No HN password provided, will only fetch public data")
            return False

        await self.setup_browser()
        page = await self.context.new_page()

        try:
            await page.goto(f"{self.hn_base_url}/login")
            await page.fill('input[name="acct"]', self.username)
            await page.fill('input[name="pw"]', self.password)
            await page.click('input[type="submit"]')
            await page.wait_for_load_state("networkidle")

            # Check if login was successful
            if await page.locator('a[href="/logout"]').count() > 0:
                logging.info("Successfully logged in to Hacker News")
                return True
            else:
                logging.error("Failed to login to Hacker News")
                return False

        except Exception as e:
            logging.error(f"Error during HN login: {e}")
            return False
        finally:
            await page.close()

    def fetch_user_favorites(self) -> List[Dict[str, Any]]:
        """Fetch user's favorited items - this requires async operation"""
        if self.use_browser:
            return asyncio.run(self._fetch_user_favorites_async())
        else:
            # If browser is disabled, just fetch submissions
            return asyncio.run(self._fetch_user_submissions())

    def fetch_user_submissions_direct(self) -> List[Dict[str, Any]]:
        """Directly fetch user's submissions without browser"""
        return asyncio.run(self._fetch_user_submissions())

    async def _fetch_user_favorites_async(self) -> List[Dict[str, Any]]:
        """Fetch user's favorited items using web scraping"""
        favorites = []

        # First try to login
        logged_in = await self.login_to_hn()
        if not logged_in:
            logging.warning("Not logged in, attempting to fetch public user data")

        try:
            # Fetch user's favorites page
            favorites_url = f"{self.hn_base_url}/favorites?id={self.username}"

            page = await self.context.new_page()
            await page.goto(favorites_url)
            await page.wait_for_load_state("networkidle")

            # Extract story links from the favorites page
            story_links = await page.locator("tr.athing").all()

            # Limit to configured max items
            story_links = story_links[: self.max_items]

            for story_element in story_links:
                try:
                    story_id = await story_element.get_attribute("id")
                    if story_id:
                        story_details = await self._fetch_story_details_async(
                            int(story_id)
                        )
                        if story_details and story_details.get("url"):
                            favorites.append(story_details)

                        # Rate limit between story fetches
                        await asyncio.sleep(0.5)

                except Exception as e:
                    logging.error(f"Error processing story element: {e}")
                    continue

            await page.close()

        except Exception as e:
            logging.error(f"Error fetching user favorites: {e}")

        # Fallback: try to get user's submitted stories if favorites failed
        if not favorites:
            logging.info("No favorites found, trying to fetch user submissions")
            favorites = await self._fetch_user_submissions()

        await self.cleanup_browser()
        return favorites

    async def _fetch_user_submissions(self) -> List[Dict[str, Any]]:
        """Fallback: fetch user's submitted stories"""
        try:
            user_data = self._make_request(f"user/{self.username}.json")
            if not user_data or "submitted" not in user_data:
                logging.warning(f"No submitted stories found for user: {self.username}")
                return []

            submitted_ids = user_data["submitted"][
                : self.max_items
            ]  # Limit to configured max

            stories = []
            for item_id in submitted_ids:
                story = await self._fetch_story_details_async(item_id)
                if story and story.get("url"):  # Only stories with URLs
                    stories.append(story)
                await asyncio.sleep(0.1)  # Rate limit

            return stories

        except Exception as e:
            logging.error(f"Error fetching user submissions: {e}")
            return []

    async def _fetch_story_details_async(
        self, story_id: int
    ) -> Optional[Dict[str, Any]]:
        """Async wrapper for fetch_story_details"""
        return self._fetch_story_details(story_id)

    def _fetch_story_details(self, story_id: int) -> Optional[Dict[str, Any]]:
        """Fetch details for a specific story"""
        story_data = self._make_request(f"item/{story_id}.json")
        if not story_data:
            return None

        # Only process stories (not comments, polls, etc.)
        if story_data.get("type") != "story":
            return None

        # Convert Unix timestamp to ISO format
        timestamp = None
        if "time" in story_data:
            timestamp = datetime.fromtimestamp(
                story_data["time"], tz=timezone.utc
            ).isoformat()

        return {
            "id": story_data.get("id"),
            "title": story_data.get("title", ""),
            "url": story_data.get("url"),  # May be None for Ask HN posts
            "score": story_data.get("score", 0),
            "by": story_data.get("by", ""),
            "time": timestamp,
            "descendants": story_data.get("descendants", 0),  # Number of comments
            "kids": story_data.get("kids", []),  # Comment IDs
            "type": story_data.get("type"),
            "text": story_data.get("text", ""),  # For Ask HN posts
        }

    async def cleanup_browser(self):
        """Cleanup browser resources"""
        if self.browser:
            await self.browser.close()
        if self.playwright_instance:
            await self.playwright_instance.stop()
