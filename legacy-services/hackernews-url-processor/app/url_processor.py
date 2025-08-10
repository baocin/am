import logging
import random
import requests
import trafilatura
import os
from datetime import datetime
from playwright.async_api import async_playwright
from typing import Dict, Any, Optional
import PyPDF2
import io


class URLProcessor:
    def __init__(self):
        """Initialize URL processor"""
        self.playwright_instance = None
        self.browser = None
        self.context = None

        # Configuration
        self.enable_screenshots = (
            os.getenv("LOOM_URL_PROCESSOR_ENABLE_SCREENSHOTS", "true").lower() == "true"
        )
        self.pdf_max_pages = int(os.getenv("LOOM_URL_PROCESSOR_PDF_MAX_PAGES", "100"))
        self.text_max_chars = int(
            os.getenv("LOOM_URL_PROCESSOR_TEXT_MAX_CHARS", "50000")
        )
        self.request_timeout = int(
            os.getenv("LOOM_URL_PROCESSOR_REQUEST_TIMEOUT", "30")
        )
        self.screenshot_timeout = int(
            os.getenv("LOOM_URL_PROCESSOR_SCREENSHOT_TIMEOUT", "10000")
        )

        # User agents for rotation
        self.user_agents = [
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:89.0) Gecko/20100101 Firefox/89.0",
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.101 Safari/537.36",
        ]

    async def setup_browser(self):
        """Setup browser for screenshot capture"""
        if not self.playwright_instance:
            self.playwright_instance = await async_playwright().start()

            user_agent = random.choice(self.user_agents)
            self.browser = await self.playwright_instance.chromium.launch(headless=True)

            self.context = await self.browser.new_context(
                viewport={"width": 1280, "height": 720}, user_agent=user_agent
            )

    async def process_url(
        self, url: str, metadata: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """Process a URL and extract content, text, and screenshot"""
        try:
            # Determine content type and processing method
            if url.lower().endswith(".pdf"):
                return await self._process_pdf(url, metadata)
            else:
                return await self._process_webpage(url, metadata)

        except Exception as e:
            logging.error(f"Error processing URL {url}: {e}")
            return None

    async def _process_pdf(
        self, url: str, metadata: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """Process PDF documents"""
        try:
            # Download PDF
            response = requests.get(
                url,
                timeout=self.request_timeout,
                headers={"User-Agent": random.choice(self.user_agents)},
            )
            response.raise_for_status()

            # Extract text from PDF
            pdf_content = io.BytesIO(response.content)
            pdf_reader = PyPDF2.PdfReader(pdf_content)

            text_content = ""
            num_pages = min(len(pdf_reader.pages), self.pdf_max_pages)
            for i in range(num_pages):
                text_content += pdf_reader.pages[i].extract_text() + "\n"

            # Limit text length
            if len(text_content) > self.text_max_chars:
                text_content = text_content[: self.text_max_chars] + "\n[Truncated...]"

            # Clean up text
            text_content = text_content.strip()

            return {
                "url": url,
                "content_type": "application/pdf",
                "title": metadata.get("title", ""),
                "text_content": text_content,
                "num_pages": len(pdf_reader.pages),
                "timestamp": datetime.now().isoformat(),
                "screenshot_data": None,  # PDFs don't have screenshots
            }

        except Exception as e:
            logging.error(f"Error processing PDF {url}: {e}")
            return None

    async def _process_webpage(
        self, url: str, metadata: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """Process web pages"""
        try:
            # First try to extract text using trafilatura (more reliable)
            downloaded = trafilatura.fetch_url(url)
            text_content = ""
            title = ""

            if downloaded:
                text_content = trafilatura.extract(downloaded) or ""
                # Try to extract title
                metadata_extracted = trafilatura.extract_metadata(downloaded)
                if metadata_extracted:
                    title = metadata_extracted.title or ""

            # If trafilatura failed, fall back to direct HTTP request
            if not text_content:
                response = requests.get(
                    url,
                    timeout=self.request_timeout,
                    headers={"User-Agent": random.choice(self.user_agents)},
                )
                response.raise_for_status()
                text_content = response.text[: self.text_max_chars]

            # Take screenshot using Playwright if enabled
            screenshot_data = None
            if self.enable_screenshots:
                screenshot_data = await self._take_screenshot(url)

            return {
                "url": url,
                "content_type": "text/html",
                "title": title or metadata.get("title", ""),
                "text_content": text_content,
                "timestamp": datetime.now().isoformat(),
                "screenshot_data": screenshot_data,
            }

        except Exception as e:
            logging.error(f"Error processing webpage {url}: {e}")
            return None

    async def _take_screenshot(self, url: str) -> Optional[bytes]:
        """Take screenshot of a webpage"""
        try:
            await self.setup_browser()

            page = await self.context.new_page()

            try:
                await page.goto(
                    url, timeout=self.request_timeout * 1000
                )  # Convert to milliseconds
                await page.wait_for_load_state(
                    "networkidle", timeout=self.screenshot_timeout
                )

                # Take full page screenshot
                screenshot_data = await page.screenshot(
                    full_page=True, timeout=self.screenshot_timeout
                )

                return screenshot_data

            finally:
                await page.close()

        except Exception as e:
            logging.error(f"Error taking screenshot of {url}: {e}")
            return None

    async def cleanup(self):
        """Cleanup browser resources"""
        if self.browser:
            await self.browser.close()
        if self.playwright_instance:
            await self.playwright_instance.stop()
