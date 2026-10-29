import os
import sys
import asyncio
import logging
import uvicorn
from multiprocessing import Process

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("privatestream.daemon")


def run_api_server():
    """Runs FastAPI ASGI server on port 8000."""
    logger.info("Starting PrivateStream FastAPI server on 0.0.0.0:8000...")
    uvicorn.run("main:app", host="0.0.0.0", port=8000, log_level="info")


def run_ingestor_worker():
    """Runs Ingestor & Telegram bot polling loop."""
    logger.info("Starting PrivateStream Ingestor & Telegram Bot...")
    from ingestor import main as ingestor_main
    try:
        asyncio.run(ingestor_main())
    except (KeyboardInterrupt, SystemExit):
        logger.info("Ingestor stopped.")


def main():
    logger.info("==================================================================")
    logger.info("🍿 Starting PrivateStream 24/7 Full Daemon (API + Telegram Bot)")
    logger.info("==================================================================")

    p1 = Process(target=run_api_server, name="API-Server")
    p2 = Process(target=run_ingestor_worker, name="Ingestor-Bot")

    p1.start()
    p2.start()

    try:
        p1.join()
        p2.join()
    except KeyboardInterrupt:
        logger.info("Shutting down daemon services...")
        p1.terminate()
        p2.terminate()
        p1.join()
        p2.join()
        logger.info("All daemon processes stopped.")


if __name__ == "__main__":
    main()
