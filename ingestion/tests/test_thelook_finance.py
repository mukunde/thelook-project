"""Tests for the thelook_finance pipeline.

Unit tests run by default. The integration test is gated by the `integration`
marker and skipped unless GOOGLE_APPLICATION_CREDENTIALS is set in the
environment. Run integration with:

    uv run pytest ingestion -m integration
"""

from __future__ import annotations

import importlib
import os
from datetime import UTC, datetime

import pytest


def test_module_imports_and_exposes_expected_symbols() -> None:
    module = importlib.import_module("thelook_finance")
    assert module.PIPELINE_NAME == "thelook_finance"
    assert module.DATASET_NAME == "thelook"
    assert hasattr(module, "users"), "users resource is exposed"
    assert hasattr(module, "run_pipeline"), "run_pipeline callable is exposed"


def test_cutoff_is_2023_01_01_utc() -> None:
    from thelook_finance import CUTOFF

    assert datetime(2023, 1, 1, tzinfo=UTC) == CUTOFF


@pytest.mark.integration
def test_pipeline_run_loads_users_to_snowflake() -> None:
    """End-to-end: runs the pipeline against real Snowflake + GCP.

    Requires:
      - .dlt/secrets.toml populated with Snowflake credentials
      - GOOGLE_APPLICATION_CREDENTIALS env var pointing to a GCP service
        account JSON with BigQuery read access on bigquery-public-data
    """
    if not os.getenv("GOOGLE_APPLICATION_CREDENTIALS"):
        pytest.skip("GOOGLE_APPLICATION_CREDENTIALS not set")

    from thelook_finance import run_pipeline

    info = run_pipeline()
    assert not info.has_failed_jobs, f"pipeline reported failed jobs: {info}"
