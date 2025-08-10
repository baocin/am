import imaplib
import email
from email.header import decode_header
import os
from datetime import datetime
import logging
from typing import List, Dict, Any
from app.shared.deduplication import content_hasher


class EmailFetcher:
    def __init__(self):
        """Initialize email fetcher with account configurations"""
        self.accounts = self._load_accounts()
        self.processed_hashes = (
            set()
        )  # Keep track of processed content hashes in memory

    def _load_accounts(self) -> List[Dict[str, Any]]:
        """Load email accounts from environment variables"""
        all_accounts = []

        # Support multiple IMAP accounts
        max_accounts = int(os.getenv("LOOM_EMAIL_MAX_ACCOUNTS", "10"))
        for i in range(1, max_accounts + 1):
            email_env = f"LOOM_EMAIL_ADDRESS_{i}"
            password_env = f"LOOM_EMAIL_PASSWORD_{i}"
            imap_server_env = f"LOOM_EMAIL_IMAP_SERVER_{i}"
            port_env = f"LOOM_EMAIL_IMAP_PORT_{i}"
            disabled_env = f"LOOM_EMAIL_DISABLED_{i}"
            name_env = f"LOOM_EMAIL_NAME_{i}"

            email_addr = os.getenv(email_env)
            if not email_addr:
                break

            account = {
                "email": email_addr,
                "password": os.getenv(password_env),
                "imap_server": os.getenv(imap_server_env, "imap.gmail.com"),
                "port": int(os.getenv(port_env, "993")),
                "disabled": os.getenv(disabled_env, "false").lower() == "true",
                "name": os.getenv(name_env, f"Email {i}"),
                "index": i,  # Add index for device_id generation
            }

            if (
                not account["disabled"]
                and account["password"]
                and account["imap_server"]
            ):
                all_accounts.append(account)
                logging.info(
                    f"Loaded email account: {account['name']} ({account['email']})"
                )

        logging.info(f"Loaded {len(all_accounts)} email accounts")
        return all_accounts

    def fetch_all_emails(self) -> List[Dict[str, Any]]:
        """Fetch emails from all configured accounts"""
        all_emails = []

        for account in self.accounts:
            try:
                emails = self._fetch_account_emails(account)
                all_emails.extend(emails)
            except Exception as e:
                logging.error(f"Error fetching emails for {account['email']}: {e}")

        return all_emails

    def _fetch_account_emails(self, account: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Fetch emails from a single account"""
        emails = []

        try:
            # Connect to IMAP server
            mail = imaplib.IMAP4_SSL(account["imap_server"], account["port"])
            mail.login(account["email"], account["password"])
            mail.select("inbox")

            # Determine search criteria from environment
            search_criteria = os.getenv("LOOM_EMAIL_SEARCH_CRITERIA", "UNSEEN")
            status, messages = mail.search(None, search_criteria)

            if messages[0]:
                email_ids = messages[0].split()
                # Limit number of emails to process
                max_emails = int(os.getenv("LOOM_EMAIL_MAX_FETCH_PER_ACCOUNT", "50"))
                email_ids = email_ids[-max_emails:]  # Get most recent emails
                logging.info(
                    f"Found {len(email_ids)} emails for {account['email']} matching criteria: {search_criteria}"
                )

                for email_id in email_ids:
                    email_id_str = email_id.decode()

                    try:
                        email_data = self._parse_email(mail, email_id, account)
                        if email_data:
                            # Check if content hash already processed
                            content_hash = email_data.get("content_hash")
                            if content_hash and content_hash in self.processed_hashes:
                                logging.debug(
                                    f"Skipping duplicate email with hash: {content_hash}"
                                )
                                continue

                            emails.append(email_data)
                            if content_hash:
                                self.processed_hashes.add(content_hash)
                    except Exception as e:
                        logging.error(f"Error parsing email {email_id_str}: {e}")

            mail.close()
            mail.logout()

        except Exception as e:
            logging.error(f"IMAP connection error for {account['email']}: {e}")

        return emails

    def _parse_email(
        self, mail, email_id: bytes, account: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Parse individual email"""
        status, msg_data = mail.fetch(email_id, "(RFC822)")

        for response_part in msg_data:
            if isinstance(response_part, tuple):
                # Parse email message
                msg = email.message_from_bytes(response_part[1])

                # Decode subject
                subject, encoding = decode_header(msg["Subject"])[0]
                if isinstance(subject, bytes):
                    try:
                        subject = subject.decode(encoding if encoding else "utf-8")
                    except UnicodeDecodeError:
                        subject = subject.decode("latin1")

                # Get sender
                sender = msg.get("From")

                # Get date
                date_tuple = email.utils.parsedate_tz(msg["Date"])
                if date_tuple:
                    date_received = datetime.fromtimestamp(
                        email.utils.mktime_tz(date_tuple)
                    )
                else:
                    date_received = datetime.now()

                # Extract body
                body = self._extract_email_body(msg)

                # Get read status
                seen = self._is_email_seen(mail, email_id)

                # Get Message-ID for content hashing (primary strategy)
                message_id = msg.get("Message-ID")

                # Generate content hash using the deduplication strategy
                try:
                    content_hash = content_hasher.generate_email_hash(
                        message_id=message_id,
                        from_address=sender,
                        to_address=account["email"],
                        date=date_received,
                        subject=subject,
                    )
                except ValueError as e:
                    logging.warning(f"Failed to generate content hash: {e}")
                    # Fallback: generate a unique hash based on account and email ID
                    content_hash = content_hasher._sha256(
                        f"{account['email']}:{email_id.decode()}"
                    )

                return {
                    "email_id": f"{account['email']}:{email_id.decode()}",
                    "content_hash": content_hash,
                    "message_id": message_id,
                    "subject": subject,
                    "sender": sender,
                    "receiver": account["email"],
                    "date_received": date_received,
                    "body": body,
                    "seen": seen,
                    "source_account": account["email"],
                    "account_name": account["name"],
                    "account_index": account.get("index", 1),
                }

        return None

    def _extract_email_body(self, msg) -> str:
        """Extract text body from email message"""
        body = ""

        if msg.is_multipart():
            for part in msg.walk():
                content_type = part.get_content_type()
                content_disposition = str(part.get("Content-Disposition"))

                if (
                    content_type == "text/plain"
                    and "attachment" not in content_disposition
                ):
                    try:
                        payload = part.get_payload(decode=True)
                        if payload:
                            body += payload.decode("utf-8", errors="ignore") + "\n\n"
                    except Exception:
                        pass
        else:
            content_type = msg.get_content_type()
            if content_type == "text/plain":
                try:
                    payload = msg.get_payload(decode=True)
                    if payload:
                        body = payload.decode("utf-8", errors="ignore")
                except Exception:
                    pass

        return body.strip()

    def _is_email_seen(self, mail, email_id: bytes) -> bool:
        """Check if email has been read"""
        try:
            status, flags_data = mail.fetch(email_id, "(FLAGS)")
            if status == "OK" and flags_data:
                flags = flags_data[0].decode()
                return "\\Seen" in flags
        except Exception:
            pass
        return False
