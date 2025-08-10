import json
import os
import random
import asyncio
import logging
from playwright.async_api import async_playwright
from typing import List, Dict, Any


class XLikesFetcher:
    def __init__(self):
        """Initialize X.com likes fetcher"""
        self.username = os.getenv("LOOM_X_USERNAME")
        self.password = os.getenv("LOOM_X_PASSWORD")
        self.phone_number = os.getenv("LOOM_X_PHONE_NUMBER")

        if not self.username or not self.password:
            raise ValueError(
                "LOOM_X_USERNAME and LOOM_X_PASSWORD environment variables are required"
            )

        self.likes_url = f"https://x.com/{self.username}/likes"
        self.session_file = "/app/sessions/x_session.json"

        self.playwright_instance = None
        self.browser = None
        self.context = None

        # User agents for rotation
        self.user_agents = [
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:89.0) Gecko/20100101 Firefox/89.0",
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.101 Safari/537.36",
        ]

    async def setup(self):
        """Setup browser and login to X.com"""
        self.playwright_instance = await async_playwright().start()
        self.browser, self.context = await self._setup_browser()
        await self._login()

    async def _setup_browser(self):
        """Setup browser with randomized configuration"""
        user_agent = random.choice(self.user_agents)
        browser = await self.playwright_instance.chromium.launch(headless=True)

        context = await browser.new_context(
            user_agent=user_agent,
            viewport={"width": 1920, "height": 1080},
            geolocation={"longitude": 40.7128, "latitude": -74.0060},
            locale="en-US",
            timezone_id="America/New_York",
            permissions=["geolocation"],
        )

        # Add scripts to avoid detection
        await context.add_init_script(
            """
            () => {
                Object.defineProperty(navigator, 'hardwareConcurrency', {
                    get: () => Math.floor(Math.random() * 8) + 2
                });
                Object.defineProperty(navigator, 'deviceMemory', {
                    get: () => Math.floor(Math.random() * 8) + 2
                });
            }
        """
        )

        return browser, context

    async def _login(self):
        """Login to X.com using stored session or credentials"""
        logging.info("Starting X.com login process")

        if os.path.exists(self.session_file):
            logging.info("Session file exists, attempting to restore session")
            try:
                with open(self.session_file, "r") as f:
                    session_data = json.load(f)
                await self.context.add_cookies(session_data["cookies"])

                page = await self.context.new_page()
                await page.goto("https://x.com")

                # Check if we're logged in by looking for home content
                await page.wait_for_timeout(3000)
                if (
                    await page.locator('[data-testid="AppTabBar_Home_Link"]').count()
                    > 0
                ):
                    logging.info("Session restored successfully")
                    await page.close()
                    return
                else:
                    logging.info("Session expired, performing fresh login")
                    await page.close()
            except Exception as e:
                logging.warning(f"Failed to restore session: {e}")

        # Perform fresh login
        await self._perform_login()

    async def _perform_login(self):
        """Perform fresh login to X.com"""
        page = await self.context.new_page()

        try:
            await page.goto("https://x.com/i/flow/login")

            # Enter username
            logging.info("Entering username")
            await self._human_like_typing(
                page,
                'div[aria-labelledby="modal-header"] input[name="text"]',
                self.username,
            )
            await page.click(
                'div[aria-labelledby="modal-header"] span:has-text("Next")'
            )
            await page.wait_for_timeout(3000)

            # Check if password field is available or if phone number is required
            password_field = await page.query_selector(
                'div[aria-labelledby="modal-header"] input[name="password"]'
            )
            login_button = await page.query_selector(
                'div[aria-labelledby="modal-header"] span:has-text("Log in")'
            )

            if password_field and login_button:
                logging.info("Password field found, entering password")
                await self._human_like_typing(
                    page,
                    'div[aria-labelledby="modal-header"] input[name="password"]',
                    self.password,
                )
                await page.click(
                    'div[aria-labelledby="modal-header"] span:has-text("Log in")'
                )
            else:
                logging.info("Phone number required, entering phone number")
                if not self.phone_number:
                    raise ValueError(
                        "X_PHONE_NUMBER environment variable is required for this account"
                    )

                await self._human_like_typing(
                    page,
                    'div[aria-labelledby="modal-header"] input[name="text"]',
                    self.phone_number,
                )
                await page.click(
                    'div[aria-labelledby="modal-header"] span:has-text("Next")'
                )
                await page.wait_for_timeout(2000)

                await self._human_like_typing(
                    page,
                    'div[aria-labelledby="modal-header"] input[name="password"]',
                    self.password,
                )
                await page.click(
                    'div[aria-labelledby="modal-header"] span:has-text("Log in")'
                )

            # Wait for successful login
            try:
                await page.wait_for_url("https://x.com/home", timeout=30000)
                logging.info("Successfully logged in to X.com")
                await self._save_session()
            except Exception as e:
                logging.error(f"Login may have failed: {e}")

        finally:
            await page.close()

    async def _save_session(self):
        """Save current session to file"""
        try:
            storage_state = await self.context.storage_state()
            with open(self.session_file, "w") as f:
                json.dump(storage_state, f)
            logging.info("Session saved successfully")
        except Exception as e:
            logging.error(f"Failed to save session: {e}")

    async def scrape_likes(self) -> List[Dict[str, Any]]:
        """Scrape liked tweets from X.com"""
        page = await self.context.new_page()
        liked_tweets = []

        try:
            await page.goto(self.likes_url)
            # Increase timeout and use domcontentloaded instead of networkidle
            await page.wait_for_load_state("domcontentloaded", timeout=30000)
            # Give page time to render content
            await page.wait_for_timeout(3000)

            # JavaScript to extract tweet information
            js_extraction_code = """
            let processedTweetBlocks = new Set();
            let savedTweets = [];

            function extractTweetInfo(tweetBlock) {
                const tweetTextElement = tweetBlock.querySelector('[data-testid="tweetText"]');
                const tweetText = tweetTextElement ? tweetTextElement.innerText : "Tweet text not found";

                const profileLinkElement = tweetBlock.querySelector('[role="link"]');
                const profileLink = profileLinkElement ? profileLinkElement.href : "Profile link not found";

                const timeElement = tweetBlock.querySelector('time');
                const tweetLinkElement = timeElement ? timeElement.closest('a') : null;
                const tweetLink = tweetLinkElement ? tweetLinkElement.href : "Tweet link not found";

                const time = timeElement ? timeElement.getAttribute('datetime') : "Time not found";

                return { text: tweetText, profileLink, tweetLink, time };
            }

            function saveTweet(tweetInfo) {
                savedTweets.push(tweetInfo);
            }

            function scanAndExtract() {
                const tweetBlocks = document.querySelectorAll('article[data-testid="tweet"]');
                let newTweetsFound = 0;
                tweetBlocks.forEach(tweetBlock => {
                    const tweetBlockId = tweetBlock.getAttribute('aria-labelledby');
                    const hash = tweetBlockId ? hashString(tweetBlockId) : null;
                    if (hash && !processedTweetBlocks.has(hash)) {
                        processedTweetBlocks.add(hash);
                        const tweetInfo = extractTweetInfo(tweetBlock);
                        saveTweet(tweetInfo);
                        newTweetsFound++;
                    }
                });
                return newTweetsFound;
            }

            function hashString(str) {
                let hash = 0;
                if (str.length === 0) return hash;
                for (let i = 0; i < str.length; i++) {
                    const char = str.charCodeAt(i);
                    hash = ((hash << 5) - hash) + char;
                    hash = hash & hash;
                }
                return hash;
            }

            function getSavedTweets() {
                return savedTweets;
            }
            """

            await page.evaluate(js_extraction_code)

            # Scroll and collect ALL tweets (no limits)
            no_new_tweets_count = 0
            max_no_new_tweets = 20  # Stop after 20 scrolls with no new tweets

            import time

            start_time = time.time()

            all_tweets = []  # Initialize
            while no_new_tweets_count < max_no_new_tweets:
                # Scan for new tweets
                new_tweets_count = await page.evaluate("() => scanAndExtract()")
                all_tweets = await page.evaluate("() => getSavedTweets()")

                if new_tweets_count == 0:
                    no_new_tweets_count += 1
                else:
                    no_new_tweets_count = 0

                elapsed_time = time.time() - start_time
                elapsed_minutes = int(elapsed_time / 60)
                logging.info(
                    f"Found {len(all_tweets)} total tweets, {new_tweets_count} new this scroll (elapsed: {elapsed_minutes}m)"
                )

                # Scroll down
                await self._random_scroll(page)
                await page.wait_for_timeout(random.randint(1000, 3000))

            # Get final list of tweets
            liked_tweets = await page.evaluate("() => getSavedTweets()")
            logging.info(f"Scraping completed. Found {len(liked_tweets)} liked tweets")

        except Exception as e:
            logging.error(f"Error scraping likes: {e}")

        finally:
            await page.close()

        return liked_tweets

    async def _human_like_typing(self, page, selector: str, text: str):
        """Type text in a human-like manner"""
        for char in text:
            await page.type(selector, char)
            await asyncio.sleep(random.uniform(0.1, 0.24))

    async def _random_scroll(self, page):
        """Perform random scrolling to simulate human behavior"""
        await page.evaluate(
            """
            () => {
                const scrollAmount = Math.floor(Math.random() * 100) + window.innerHeight;
                window.scrollBy(0, scrollAmount);
            }
        """
        )

    async def cleanup(self):
        """Cleanup browser resources"""
        if self.browser:
            await self.browser.close()
        if self.playwright_instance:
            await self.playwright_instance.stop()
