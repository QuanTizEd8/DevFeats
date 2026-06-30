"""Tests for proman.test.scenarios helpers."""

from __future__ import annotations

from proman.test.scenarios import (
    FAST_NET_FAIL_ENV_VARS,
    merge_scenario_env_vars,
    network_fetch_failure_test_ids_missing_fast_config,
    scenario_expects_network_fetch_failure,
    scenario_has_fast_net_fail_config,
    scenario_injects_fast_net_fail_env,
)


def test_merge_scenario_env_vars_leaves_success_path_unchanged() -> None:
    """Success-path scenarios must not inject fast-net-fail env vars."""
    scenario = {"options": {"version": "latest"}}
    assert merge_scenario_env_vars(scenario) == {}


def test_merge_scenario_env_vars_adds_fast_fail_when_network_none() -> None:
    """standalone.network: none injects fast-net-fail env vars."""
    scenario = {"standalone": {"network": "none"}}
    assert merge_scenario_env_vars(scenario) == FAST_NET_FAIL_ENV_VARS


def test_merge_scenario_env_vars_adds_fast_fail_when_fast_net_fail_true() -> None:
    """fast_net_fail: true injects fast-net-fail env vars."""
    scenario = {"fast_net_fail": True}
    assert merge_scenario_env_vars(scenario) == FAST_NET_FAIL_ENV_VARS


def test_merge_scenario_env_vars_explicit_env_vars_win() -> None:
    """Scenario env_vars override injected fast-net-fail defaults."""
    scenario = {
        "standalone": {"network": "none"},
        "env_vars": {"DEVFEATS_NET_FETCH_RETRIES": "3"},
    }
    merged = merge_scenario_env_vars(scenario)
    assert merged["DEVFEATS_NET_FETCH_RETRIES"] == "3"
    assert merged["DEVFEATS_NET_FETCH_DELAY"] == "0"


def test_scenario_injects_fast_net_fail_env() -> None:
    """Only fast_net_fail and network:none trigger env injection."""
    assert scenario_injects_fast_net_fail_env({"fast_net_fail": True})
    assert scenario_injects_fast_net_fail_env({"standalone": {"network": "none"}})
    assert not scenario_injects_fast_net_fail_env(
        {"env_vars": {"DEVFEATS_NET_FETCH_RETRIES": "1"}},
    )


def test_scenario_expects_network_fetch_failure_detects_blocked_network() -> None:
    """Blocked-network install_failure checks are detected."""
    checks = {
        "github_api_unreachable_network_isolated": {
            "description": "Verify install fails when the network is blocked.",
            "checks": [
                {
                    "kind": "install_failure",
                    "pattern": "GitHub API unreachable",
                },
            ],
        },
    }
    assert scenario_expects_network_fetch_failure(
        checks,
        "github_api_unreachable_network_isolated",
    )


def test_scenario_expects_network_fetch_failure_ignores_local_failures() -> None:
    """Local validation failures are not treated as network fetch failures."""
    checks = {
        "if_exists_fail": {
            "checks": [
                {
                    "kind": "install_failure",
                    "pattern": "failing (if_exists=fail)",
                },
            ],
        },
    }
    assert not scenario_expects_network_fetch_failure(checks, "if_exists_fail")


def test_scenario_has_fast_net_fail_config() -> None:
    """Fast-net-fail config is recognized from flag, network, or explicit env."""
    assert scenario_has_fast_net_fail_config({"fast_net_fail": True})
    assert scenario_has_fast_net_fail_config({"standalone": {"network": "none"}})
    assert scenario_has_fast_net_fail_config(
        {"env_vars": {"DEVFEATS_NET_FETCH_RETRIES": "1"}},
    )
    assert not scenario_has_fast_net_fail_config({"options": {"version": "latest"}})


def test_network_fetch_failure_test_ids_missing_fast_config() -> None:
    """Return offending test IDs only when fast-net-fail config is absent."""
    checks = {
        "blocked_net": {
            "checks": [
                {
                    "kind": "install_failure",
                    "pattern": "GitHub API unreachable",
                },
            ],
        },
        "local_fail": {
            "checks": [
                {
                    "kind": "install_failure",
                    "pattern": "failing (if_exists=fail)",
                },
            ],
        },
    }
    scenario = {
        "expect_install_failure": True,
        "tests": ["blocked_net", "local_fail"],
    }
    assert network_fetch_failure_test_ids_missing_fast_config(checks, scenario) == [
        "blocked_net",
    ]
    assert (
        network_fetch_failure_test_ids_missing_fast_config(
            checks,
            {**scenario, "fast_net_fail": True},
        )
        == []
    )
