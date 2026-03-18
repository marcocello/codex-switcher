# Usage Token Refresh on 401

## Behavior
- For OAuth-backed ChatGPT accounts, usage refresh calls `https://chatgpt.com/backend-api/wham/usage` with the stored access token.
- If usage returns HTTP `401`, the app uses the stored `refresh_token` to obtain a new access token from the OAuth token endpoint using a JSON payload (`client_id`, `grant_type=refresh_token`, `refresh_token`).
- After a successful token refresh, the app retries usage once with the refreshed access token.
- Refreshed credential fields are persisted to local account state so subsequent refreshes do not keep using stale tokens.
- If no refresh token is available, usage remains unavailable and reports an HTTP `401` usage error.
- If refresh fails with known backend codes (`refresh_token_expired`, `refresh_token_reused`, `refresh_token_invalidated`), the app shows an actionable message to re-add the account.

## Scenarios
```gherkin
Feature: Usage refresh for expired OAuth tokens

  Scenario: USG-401-01 refresh token recovers usage after an expired access token
    Given an OAuth ChatGPT account with an expired access token and a valid refresh token
    When usage refresh receives HTTP 401 from the usage endpoint
    Then the app refreshes OAuth tokens
    And retries the usage request once with the new access token
    And shows usage data without an error

  Scenario: USG-401-02 refreshed credentials are persisted
    Given usage refresh obtained new OAuth tokens after a 401 response
    When account state is saved
    Then the stored credential for that account contains the refreshed token values

  Scenario: USG-401-03 missing refresh token keeps unauthorized usage state
    Given an OAuth ChatGPT account with an expired access token and no refresh token
    When usage refresh receives HTTP 401 from the usage endpoint
    Then the app does not attempt token refresh
    And usage remains unavailable with a 401 usage error

  Scenario: USG-401-04 revoked refresh token surfaces re-auth guidance
    Given an OAuth ChatGPT account whose refresh token is revoked
    When usage refresh receives HTTP 401 from the usage endpoint and refresh attempt returns code refresh_token_invalidated
    Then usage remains unavailable
    And the app message tells the user to re-add the account
```
