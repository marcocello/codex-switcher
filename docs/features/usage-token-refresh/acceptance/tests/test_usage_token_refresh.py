from __future__ import annotations

import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[5]


def run_swift_filter(filter_name: str) -> None:
    cmd = ["swift", "test", "--filter", filter_name]
    result = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    assert result.returncode == 0, (
        f"swift test filter failed: {filter_name}\n"
        f"STDOUT:\n{result.stdout}\n"
        f"STDERR:\n{result.stderr}"
    )


def test_usg_401_01_refresh_token_recovers_usage() -> None:
    """USG-401-01"""
    run_swift_filter("usageFetcherRefreshesTokenOn401AndRetries")


def test_usg_401_02_refreshed_credentials_are_persisted() -> None:
    """USG-401-02"""
    run_swift_filter("refreshUsagePersistsRefreshedCredential")


def test_usg_401_03_missing_refresh_token_keeps_unauthorized_state() -> None:
    """USG-401-03"""
    run_swift_filter("usageFetcherReturns401WhenRefreshTokenMissing")


def test_usg_401_04_revoked_refresh_token_shows_reauth_guidance() -> None:
    """USG-401-04"""
    run_swift_filter("usageFetcherMapsInvalidatedRefreshToken")
